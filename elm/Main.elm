module Main exposing (main)

import Api
import Browser
import Browser.Navigation as Nav
import Html exposing (Html)
import Html.Attributes as Attr
import Html.Events exposing (onClick, onInput)
import Http
import Json.Decode
import Url exposing (Url)
import Url.Parser as UrlParser exposing ((</>), (<?>), s)
import Url.Parser.Query as Query



---- MODEL ----


type alias Model =
    { navKey : Nav.Key
    , page : Route
    , email : WebResource String
    , question : String
    , answer : Maybe String
    , messages : List String
    }


type Route
    = Question
    | Unknown Url
    | AuthGitHub String String String -- db-key code state
    | AuthGoogle String String -- db-key code
    | ErrorAuthGitHub (List ( String, String ))


type WebResource a
    = NotAsked
    | Received a
    | Checking
    | Failed Http.Error


type alias Flags =
    { question : String, answer : String }


init : Json.Decode.Value -> Url -> Nav.Key -> ( Model, Cmd Msg )
init flags url key =
    let
        page =
            let
                _ =
                    Debug.log "init url" url
            in
            parseRoute url

        model_ =
            initModel key

        model =
            case Json.Decode.decodeValue decodeFlags flags of
                Ok data ->
                    { model_
                        | question = data.question
                        , answer = Just data.answer
                    }

                Err err ->
                    let
                        _ =
                            Debug.log "Could not parse initialization data" err
                    in
                    model_
    in
    case page of
        AuthGitHub dbKey code state ->
            ( { model | page = Question, email = Checking }
                |> addMessage ("GitHub code " ++ code)
            , Api.verifyMailGitHub VerifiedEmail dbKey code state
            )

        AuthGoogle dbKey code ->
            ( { model | page = Question, email = Checking }
                |> addMessage ("Google code " ++ code)
            , Api.verifyMailGoogle VerifiedEmail dbKey code
            )

        _ ->
            ( { model | page = page }, Cmd.none )


decodeFlags : Json.Decode.Decoder Flags
decodeFlags =
    Json.Decode.map2 Flags
        (Json.Decode.field "question" Json.Decode.string)
        (Json.Decode.field "answer" Json.Decode.string)


initModel : Nav.Key -> Model
initModel navKey =
    { navKey = navKey
    , page = Question
    , email = NotAsked
    , question = "What is your favorite color?"
    , answer = Nothing
    , messages = []
    }



---- UPDATE ----


type Msg
    = LinkClicked Browser.UrlRequest
    | UrlChange Url
    | Answer String
    | GetGitHubUrl
    | GetGitHubUrlResponse (Result Http.Error String)
    | GetGoogleUrl
    | GetGoogleUrlResponse (Result Http.Error String)
    | VerifiedEmail (Result Http.Error String)
    | Restart


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        LinkClicked urlRequest ->
            let
                _ =
                    Debug.log "LinkClicked" urlRequest
            in
            case urlRequest of
                Browser.Internal url ->
                    ( model
                    , Nav.pushUrl model.navKey (Url.toString url)
                      -- triggers UrlChange
                    )

                Browser.External href ->
                    let
                        _ =
                            Debug.log "Would like to move to external url" href
                    in
                    -- ( model, Nav.load href )
                    ( model, Cmd.none )

        UrlChange location ->
            ( { model | page = parseRoute location }
            , Cmd.none
            )

        Answer string ->
            ( { model | answer = Just string }, Cmd.none )

        GetGitHubUrl ->
            ( model, Api.getAuthUrl "github" GetGitHubUrlResponse model )

        GetGitHubUrlResponse response ->
            case
                response
                    |> Debug.log "GetGitHubUrlResponse"
            of
                Ok url ->
                    ( model, Nav.load url )

                Err err ->
                    ( model, Cmd.none )

        GetGoogleUrl ->
            ( model, Api.getAuthUrl "google" GetGoogleUrlResponse model )

        GetGoogleUrlResponse response ->
            case
                response
                    |> Debug.log "GetGoogleUrlResponse"
            of
                Ok url ->
                    ( model, Nav.load url )

                Err err ->
                    ( model, Cmd.none )

        VerifiedEmail (Ok email) ->
            ( { model | page = Question, email = Received email }
                |> addMessage ("verified " ++ email)
            , Nav.pushUrl model.navKey "/"
            )

        VerifiedEmail (Err err) ->
            ( { model | email = Failed err }
                |> addMessage (httpErrorToString err)
            , Cmd.none
            )

        Restart ->
            ( initModel model.navKey, Cmd.none )


parseRoute : Url -> Route
parseRoute url =
    UrlParser.parse route url
        |> Maybe.withDefault (Unknown url)


route : UrlParser.Parser (Route -> a) a
route =
    UrlParser.oneOf
        [ UrlParser.map Question UrlParser.top
        , UrlParser.map authGitHub authGitHubParser
        , UrlParser.map authGoogle authGoogleParser
        , UrlParser.map gitHubErrorAuth gitHubErrorAuthParser
        ]


addMessage : String -> Model -> Model
addMessage string model =
    let
        _ =
            Debug.log "addMessage" string
    in
    { model | messages = string :: model.messages }


authGitHub : String -> Maybe String -> Maybe String -> Route
authGitHub dbKey maybeCode maybeState =
    case ( maybeCode, maybeState ) of
        ( Just code, Just state ) ->
            AuthGitHub dbKey code state

        _ ->
            Question


authGitHubParser : UrlParser.Parser (String -> Maybe String -> Maybe String -> a) a
authGitHubParser =
    -- successful redirect /auth/github/<key>?code=<str>&state=<str>
    s "auth" </> s "github" </> UrlParser.string <?> Query.string "code" <?> Query.string "state"


authGoogle : Maybe String -> Maybe String -> Route
authGoogle maybeKey maybeCode =
    case ( maybeKey, maybeCode ) of
        ( Just key, Just code ) ->
            AuthGoogle key code

        _ ->
            Question


authGoogleParser : UrlParser.Parser (Maybe String -> Maybe String -> a) a
authGoogleParser =
    -- successful redirect /auth/google?state=<key>&code=<str>#
    s "auth" </> s "google" <?> Query.string "state" <?> Query.string "code"


gitHubErrorAuth : Maybe String -> Maybe String -> Maybe String -> Maybe String -> Route
gitHubErrorAuth error description uri state =
    -- Note: This should be handled on the server side
    [ ( "error", error ), ( "description", description ), ( "uri", uri ), ( "state", state ) ]
        |> List.filterMap dropUseless
        |> ErrorAuthGitHub


gitHubErrorAuthParser : UrlParser.Parser (Maybe String -> Maybe String -> Maybe String -> Maybe String -> a) a
gitHubErrorAuthParser =
    -- see https://developer.github.com/apps/managing-oauth-apps/troubleshooting-authorization-request-errors/
    s "auth" </> s "github" <?> Query.string "error" <?> Query.string "error_description" <?> Query.string "error_uri" <?> Query.string "state"


dropUseless : ( a, Maybe b ) -> Maybe ( a, b )
dropUseless ( key, maybeValue ) =
    case maybeValue of
        Just value ->
            Just ( key, value )

        Nothing ->
            Nothing



---- VIEW ----


view : Model -> Browser.Document Msg
view model =
    { title = "OAuth example"
    , body =
        [ Html.div [ Attr.class "centered" ]
            [ Html.main_ [ Attr.class "column" ] <|
                case model.page of
                    Question ->
                        question model

                    AuthGitHub dbKey code state ->
                        -- this route is currently never displayed
                        question model

                    AuthGoogle dbKey code ->
                        -- this route is currently never displayed
                        question model

                    ErrorAuthGitHub errors ->
                        [ Html.ul [] <|
                            List.map
                                (\( key, value ) ->
                                    Html.li []
                                        [ Html.b [] [ Html.text <| key ++ ": " ]
                                        , Html.text value
                                        ]
                                )
                                errors
                        ]

                    Unknown location ->
                        [ Html.h2 [] [ Html.text "Unknown page" ]

                        -- , Html.p [] [ Html.text location.pathname ]
                        , Html.p [] [ Html.text "todo" ]
                        ]
            , footer model
            ]
        ]
    }


question : Model -> List (Html Msg)
question model =
    [ Html.h1 [] [ Html.text model.question ]
    , Html.label []
        [ Html.text "Answer "
        , Html.input
            [ onInput Answer
            , Attr.value <|
                Maybe.withDefault "" model.answer
            ]
            []
        ]
    , Html.hr [] []
    , Html.h2 [] [ Html.text "Email" ]
    , case model.email of
        NotAsked ->
            Html.div [ Attr.class "column" ]
                [ Html.button
                    [ Attr.class "button github"
                    , onClick GetGitHubUrl
                    ]
                    [ Html.text "Provide with Github" ]
                , Html.button
                    [ Attr.class "button google"
                    , onClick GetGoogleUrl
                    ]
                    [ Html.text "Provide with Google Signin" ]
                ]

        Received email ->
            Html.p [] [ Html.text email ]

        Checking ->
            Html.div [ Attr.class "loader" ] [ Html.text "Loading..." ]

        Failed error ->
            Html.code [] [ Html.text <| httpErrorToString error ]
    ]


httpErrorToString : Http.Error -> String
httpErrorToString error =
    let
        _ =
            Debug.log "httpErrorToString" error
    in
    case error of
        Http.BadUrl string ->
            "BadUrl: " ++ string

        Http.Timeout ->
            "Timeout"

        Http.NetworkError ->
            "NetworkError"

        Http.BadStatus { url, status, headers, body } ->
            -- type alias Response body =
            --     { url : String
            --     , status :
            --         { code : Int
            --         , message : String
            --         }
            --     , headers : Dict String String
            --     , body : body
            --     }
            "BadStatus: " ++ String.fromInt status.code ++ " '" ++ status.message ++ "'"

        Http.BadPayload string response ->
            "BadPayload: " ++ string


footer : Model -> Html Msg
footer model =
    let
        page =
            case model.page of
                Question ->
                    "Question"

                Unknown location ->
                    "Unknown"

                AuthGitHub dbKey code state ->
                    "GitHub Authentication code received"

                AuthGoogle dbKey code ->
                    "Google Authentication code received"

                ErrorAuthGitHub _ ->
                    "GitHub Authentication failed"
    in
    Html.footer []
        [ Html.a [ Attr.href "/", onClick Restart ] [ Html.text "Start again" ]
        , Html.span [] [ Html.text <| "Page: " ++ page ]
        ]



---- PROGRAM ----


main : Program Json.Decode.Value Model Msg
main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = always Sub.none
        , onUrlChange = UrlChange
        , onUrlRequest = LinkClicked
        }
