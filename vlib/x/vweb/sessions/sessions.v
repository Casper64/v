module sessions

import crypto.sha256
import crypto.hmac
import encoding.base64
import net.http
import rand
import time
import x.vweb

const session_id_length = 32

// create and return a random session id and its signed version. You can directly use
// the signed version as a cookie value
pub fn new_session_id(secret []u8) (string, string) {
	sid := rand.hex(sessions.session_id_length)

	hashed := hmac.new(secret, sid.bytes(), sha256.sum, sha256.block_size)

	// seperate session id and hmac with a `.`
	return sid, '${sid}.${base64.url_encode(hashed)}'
}

// verify the signed session id with `secret`. This function returns the session id
// and if the session id is valid
pub fn verify_session_id(raw_sid string, secret []u8) (string, bool) {
	parts := raw_sid.split('.')
	if parts.len != 2 {
		return '', false
	}

	sid := parts[0]
	actual_hmac := base64.url_decode(parts[1])

	new_hmac := hmac.new(secret, sid.bytes(), sha256.sum, sha256.block_size)
	// use `hmac.equal` to prevent leaking timing information
	return sid, hmac.equal(actual_hmac, new_hmac)
}

pub struct CurrentSession[T] {
pub mut:
	session_id   string
	session_data ?T
}

pub struct CookieOptions {
	cookie_name string = 'sid'
	domain      string
	http_only   bool          = true
	path        string        = '/'
	same_site   http.SameSite = .same_site_strict_mode
	secure      bool = true
}

@[heap]
pub struct Sessions[T] {
pub:
	secret         []u8          @[required]
	cookie_options CookieOptions
	// max age of session data and id, default is 30 days
	max_age time.Duration = time.hour * 24 * 30
pub mut:
	store Store[T] @[required]
}

// generate a new session id and set a Set-Cookie header on the response
pub fn (mut s Sessions[T]) set_session_id[X](mut ctx X) string {
	sid, signed := new_session_id(s.secret)

	ctx.set_cookie(http.Cookie{
		value: signed
		max_age: s.max_age
		domain: s.cookie_options.domain
		http_only: s.cookie_options.http_only
		name: s.cookie_options.cookie_name
		path: s.cookie_options.path
		same_site: s.cookie_options.same_site
		secure: s.cookie_options.secure
	})
	// indicate that the response should not be cached: we don't want the session id cookie
	// to be cached by the browser, or any other agent
	// https://datatracker.ietf.org/doc/html/rfc7234#section-5.2.1.4
	ctx.res.header.add(.cache_control, 'no-cache="Set-Cookie"')

	return sid
}

// validate the current session, returns the session id and the validation status
pub fn (mut s Sessions[T]) validate_session[X](ctx X) (string, bool) {
	cookie := ctx.get_cookie(s.cookie_options.cookie_name) or { return '', false }

	return verify_session_id(cookie, s.secret)
}

// get the data associated with the current session, if it exists
pub fn (mut s Sessions[T]) get[X](ctx X) ?T {
	sid := s.get_session_id(ctx) or { return none }
	return s.store.get(sid, s.max_age)
}

// destroy the data for the current session
pub fn (mut s Sessions[T]) destroy[X](mut ctx X) {
	if sid := s.get_session_id(ctx) {
		s.store.destroy(sid)
		ctx.session_data = none
	}
}

// logout destroys the data for the current session and removes
// the session id Cookie
pub fn (mut s Session[T]) logout[X](mut ctx X) {
	s.destroy(mut ctx)
	ctx.set_cookie(http.Cookie{
		name: s.cookie_options.cookie_name
		value: ''
		max_age: 0
	})
}

// save `data` for the current session
pub fn (mut s Sessions[T]) save[X](mut ctx X, data T) {
	if sid := s.get_session_id(ctx) {
		s.store.set(sid, data)
		ctx.CurrentSession.session_data = data
	} else {
		eprintln('[vweb.sessions] error: trying to save data without a valid session!')
	}
}

// Save `data` for the current session and reset the session id.
// You should use this function when the authentication or authorization status changes
// e.g. when a user signs in or switches between accounts/permissions.
// This function also destroys the data associtated to the old session id.
pub fn (mut s Sessions[T]) resave[X](mut ctx X, data T) {
	if sid := s.get_session_id(ctx) {
		s.store.destroy(sid)
	}

	new_sid := s.set_session_id(mut ctx)
	s.store.set(new_sid, data)
	ctx.CurrentSession.session_data = data
}

// get the current session id, if it is set
pub fn (s &Sessions[T]) get_session_id[X](ctx X) ?string {
	// first check session id from `ctx`
	sid_from_ctx := ctx.CurrentSession.session_id
	if sid_from_ctx != '' {
		return sid_from_ctx
	} else if cookie := ctx.get_cookie(s.cookie_options.cookie_name) {
		// check request headers for the session_id cookie
		a := cookie.split('.')
		return a[0]
	} else {
		// check the Set-Cookie headers on the response for a session id
		for cookie in ctx.res.cookies() {
			if cookie.name == s.cookie_options.cookie_name {
				return cookie.value
			}
		}

		// No session id is set
		return none
	}
}

// You can add this middleware to your vweb app to ensure a valid session always
// exists. If a valid session exists the session data will be loaded into
// `session_data`, else a new session id will be generated.
// You have to pass the Context type as the generic type
// Example: app.use(app.sessions.middleware[Context]())
pub fn (mut s Sessions[T]) middleware[X]() vweb.MiddlewareOptions[X] {
	return vweb.MiddlewareOptions[X]{
		handler: fn [mut s] [T, X](mut ctx X) bool {
			// a session id is retrieved from the client, so it must be considered
			// untrusted and has to be verified on every request
			sid, valid := s.validate_session(ctx)

			if !valid {
				// invalid session id, so create a new one
				ctx.CurrentSession.session_id = s.set_session_id(mut ctx)
				return true
			}

			ctx.CurrentSession.session_id = sid
			if data := s.store.get(sid, s.max_age) {
				ctx.CurrentSession.session_data = data
			}

			return true
		}
	}
}
