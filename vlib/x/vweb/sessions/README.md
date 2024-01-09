# Sessions

A sessions module for web projects. You can also use this module outside of vweb
see [here](#using-sessions-outside-vweb).

## Usage

There 

## Getting Started

To start using sessions in vweb embed `sessions.CurrentSession` on the
Context struct and add `sessions.Sessions` to the app struct. We must also pass the type
of our session data. 

For any further example code we will use the `User` struct.
**Example:**
```v
import x.vweb
import x.vweb.sessions

pub struct User {
pub mut:
	name	 string
	verified bool
}

pub struct Context {
	vweb.Context
	// By embedding the CurrentSession struct we can directly access the current session id
	// and any associated session data. Set the session data type to `User`
	sessions.CurrentSession[User]
}

pub struct App {
pub mut:
	// this struct contains the store that holds all session data it also provides
	// an easy way to manage sessions in your vweb app. Set the session data type to `User`
	sessions &sessions.Sessions[User]
}
```

Next we need to create the `&sessions.Sessions[User]` instance for our app. This 
struct provides functionality to easier manage sessions in a vweb app. 

### Session Stores

To create `sessions.Sessions` We must specify a "store" which handles the session data.
Currently vweb provides two options for storing session data:

1. The `MemoryStore[T]` stores session data in memory only using the `map` datatype. 
2. The `DBStore[T]` stores session data in a database by encoding the session data to JSON.

It is possible to create your own session store, see [custom stores](#custom-stores).

### Starting the App

For this example we will use the memory store.

**Example:**
```v ignore
fn main() {
	mut app := &App{
		store: sessions.MemoryStore[User]{}
		// use your own secret which will be used to verify session id's
		secret: 'my secret'.bytes()
	}
	
	vweb.run[App, Context](mut app, 8080)
}
```

### Middleware

The `sessions.Sessions` struct provides a middleware handler. This handler will execute 
before your own route handlers and will verify the current session and fetch any associated
session data and load it into `sessions.CurrentSession`, which is embedded on the Context struct.

> **Note:**
> It is recommended to use the middleware, so the sessions are always verfied
> and loaded correctly.

**Example:**
```v
pub struct App {
    // embed the Middleware struct from vweb
    vweb.Middleware[Context]
pub mut:
	// this struct contains the store that holds all session data it also provides
	// an easy way to manage sessions in your vweb app. Set the session data type to `User`
	sessions &sessions.Sessions[User]
}

fn main() {
	mut app := &App{
		store: sessions.MemoryStore[User]{}
		// use your own secret which will be used to verify session id's
		secret: 'my secret'.bytes()
	}

    // register the sessions middleware
    app.use(app.sessions.middleware[Context]())
	
	vweb.run[App, Context](mut app, 8080)
}
```

You can now start using sessions with vweb!

### Usage in endpoint handlers

#### Using Session Data

Because `sessions.CurrentSession` is embedded on the Context struct we can directly
access any session data via `ctx.session_data`. This field is an option, it will be `none`
if no data is set.

**Example:**
```v
pub fn (app &App) index(mut ctx Context) vweb.Result {
	// check if a user is logged in
	if user := ctx.session_data {
		return ctx.text('Welcome ${user.name}! Verification status: ${user.verified}')
	} else {
		// user is not logged in
		return ctx.text('You are not logged in :(')
	}
}
```

#### Saving / updating session data

You can use the `save` method to update and save any session data.

The following endpoint checks if a session exists, if it doesn't inform the
user that they need to login.

If a session does exists the users name is updated to the `name` query parameter,
you can use this route via `http://localhost:8080/save?name=myname`. And if the
query parameter is not passed an error 400 (bad request) is returned.

**Example:**
```v
pub fn (mut app App) save(mut ctx Context) vweb.Result {
	// check if there is a session
	app.sessions.get(ctx) or { return ctx.request_error('You are not logged in :(') }

	if name := ctx.query['name'] {
		// update the current user
		app.sessions.save(mut ctx, User{
			name: name
		})
		return ctx.redirect('/', .see_other)
	} else {
		// send HTTP 400 error
		return ctx.request_error('query parameter "name" must be present!')
	}
}
```

If the authentication or authorization status of a session changes you should use the `resave`
method instead of `save`. `resave` will set a new session id and destroy the data of the old
sessions. For security reasons it is recommended to use this best practice.

**Example:**
```v
pub fn (mut app App) login(mut ctx Context) vweb.Result {
	// use resave, because the authentication status of the session changes.
	// this function will set a new session id and destroy old session data
	app.sessions.resave(mut ctx, User{
		name: '[no name provided]'
	})
	return ctx.text('You are now logged in!')
}
```

#### Destroying data / logging out

If a user logs out you can use the `logout` method to destroy the session data and 
clear the session id cookie. If you only want to destroy the session data use the `destroy` 
method.

**Example:**
```v
pub fn (mut app App) logout(mut ctx Context) vweb.Result {
	app.sessions.logout(mut ctx)
	return ctx.text('You are now logged out!')
}
```

## Configuration



## Custom Stores

You can easily create your own custom store in order to control how session data is 
stored and retrieved. Each session store needs to implement the `Store[T]` interface.

```v ignore
pub interface Store[T] {
mut:
	// get the current session data if the id exists and if it's not expired
	get(sid string, max_age time.Duration) ?T
	// destroy session data for `sid`
	destroy(sid string)
	// set session data for `val`
	set(sid string, val T)
}

// get data from all sessions, optional to implement
pub fn (mut s Store) all[T]() []T {
	return []T{}
}

// clear all session data, optional to implement
pub fn (mut s Store) clear[T]() {}
```

Only the `get`, `destroy` and `set` methods are required to implement.

### Session Expire time

The `max_age` argument in `get` can be used to check whether the session is still valid. 
The database and memory store both check the expiration time from the time the session data
first inserted.

## Using sessions outside of vweb
A