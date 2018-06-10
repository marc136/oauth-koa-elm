# GitHub OAuth example

## Running
Install the dependencies with `npm install` or `yarn`.  
Then compile the elm code to javascript and start the node.js server with `npm start --silent` or `yarn start`.


## Steps
0. Open the web app and start answering the question, then use GitHub to provide your email address
1. Post current state to /auth/github/get-url
    - App state is stored in db with a random key
3. Receive authentication URL
    - Contains a csrf token
    - Redirect url contains the key to restore the app state
4. Redirect to GitHub servers
    - User authenticates and allows access
5. Redirect to /auth/github/<key>
    - Rehydrate session on server
6. App displays current state
7. App communicates with server to retrieve an email address
    - App posts to /auth/github with body `code` and `state`
    - Server retrieves an access token from GitHub
    - Server queries GitHub for user data
    - Server answers to app with user's email
8. App displays authenticated email address


## Server

| HTTP | Route | Description |
|------|-------|-------------|
| GET  | /index | Serves the web app |
| POST | /auth/github/get-url | Receives the web app state and returns the redirect URL |
| GET  | /auth/github/<key> | Serves the web app with saved web app state |
| POST | /auth/github/<key> | Receives the *user code*, communicates with GitHub, and returns the user's email address |
