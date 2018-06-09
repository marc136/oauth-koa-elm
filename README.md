# GitHub OAuth example

## Steps
1. Post current state to /auth/github/get-url
    - App state is stored in db with a random key
3. Receive authentication URL
    - Contains a csrf token
    - Redirect url contains the key to restore the app state
4. Redirect to GitHub servers
    - User authenticates
5. Redirect to /auth/github/<key>
    - Rehydrate session on server
6. App displays current state
7. App communicates with server to retrieve an email address
    - App posts to /auth/github with body `code` and `state`
    - Server retrieves an access token from GitHub
    - Server queries GitHub for user data
    - Server answers to app with user's email
8. App displays authenticated email address

