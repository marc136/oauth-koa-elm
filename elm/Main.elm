module Main exposing (..)

import Api
import Html exposing (Html)
import Html.Attributes as Attr
import Html.Events exposing (onClick, onInput)
import Http exposing (encodeUri)
import Json.Decode
import Navigation exposing (Location)
import UrlParser exposing ((</>), (<?>), s, stringParam)


---- MODEL ----


type alias Model =
    { page : Route
    , email : WebResource String
    , question : String
    , answer : Maybe String
    , messages : List String
    }


type Route
    = Question
    | Unknown Location
    | GitHubAuth String String String -- db-key code state
    | GitHubAuthError (List ( String, String ))


type WebResource a
    = NotAsked
    | Received a
    | Checking
    | Failed Http.Error


type alias Flags =
    { question : String, answer : String }


init : Json.Decode.Value -> Location -> ( Model, Cmd Msg )
init flags location =
    let
        page =
            parseRoute location

        model =
            case Json.Decode.decodeValue decodeFlags flags of
                Ok data ->
                    { defaultModel
                        | question = data.question
                        , answer = Just data.answer
                    }

                Err err ->
                    let
                        _ =
                            Debug.log "Could not parse initialization data" err
                    in
                    defaultModel
    in
    case page of
        GitHubAuth dbKey code state ->
            ( { model | page = Question, email = Checking }
                |> addMessage ("GitHub code " ++ code)
            , Api.verifyMailGitHub VerifiedEmail dbKey code state
            )

        _ ->
            ( { model | page = page }, Cmd.none )


decodeFlags : Json.Decode.Decoder Flags
decodeFlags =
    Json.Decode.map2 Flags
        (Json.Decode.field "question" Json.Decode.string)
        (Json.Decode.field "answer" Json.Decode.string)


defaultModel : Model
defaultModel =
    { page = Question
    , email = NotAsked
    , question = "What is your favorite color?"
    , answer = Nothing
    , messages = []
    }



---- UPDATE ----


type Msg
    = UrlChange Location
    | Answer String
    | GetGitHubUrl
    | GetGitHubUrlResponse (Result Http.Error String)
    | VerifiedEmail (Result Http.Error String)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UrlChange location ->
            ( { model | page = parseRoute location }
            , Cmd.none
            )

        Answer string ->
            ( { model | answer = Just string }, Cmd.none )

        GetGitHubUrl ->
            ( model
            , Api.getGitHubUrl GetGitHubUrlResponse model
            )

        GetGitHubUrlResponse response ->
            case
                response
                    |> Debug.log "GetGitHubUrlResponse"
            of
                Ok url ->
                    ( model, Navigation.load url )

                Err err ->
                    ( model, Cmd.none )

        VerifiedEmail (Ok email) ->
            ( { model | page = Question, email = Received email }
                |> addMessage ("verified " ++ email)
            , Navigation.newUrl "/"
            )

        VerifiedEmail (Err err) ->
            ( { model | email = Failed err }
                |> addMessage (toString err)
            , Cmd.none
            )


parseRoute : Location -> Route
parseRoute location =
    UrlParser.parsePath route location
        |> Maybe.withDefault (Unknown location)


route : UrlParser.Parser (Route -> a) a
route =
    UrlParser.oneOf
        [ UrlParser.map Question UrlParser.top
        , UrlParser.map gitHubAuth authParser
        , UrlParser.map gitHubErrorAuth authErrorParser
        ]


addMessage : String -> Model -> Model
addMessage string model =
    let
        _ =
            Debug.log "addMessage" string
    in
    { model | messages = string :: model.messages }


gitHubAuth : String -> Maybe String -> Maybe String -> Route
gitHubAuth dbKey maybeCode maybeState =
    case ( maybeCode, maybeState ) of
        ( Just code, Just state ) ->
            GitHubAuth dbKey code state

        _ ->
            Question


authParser : UrlParser.Parser (String -> Maybe String -> Maybe String -> a) a
authParser =
    -- successful redirect /auth/github/<key>?code=<str>&state=<str>
    s "auth" </> s "github" </> UrlParser.string <?> stringParam "code" <?> stringParam "state"


gitHubErrorAuth : Maybe String -> Maybe String -> Maybe String -> Maybe String -> Route
gitHubErrorAuth error description uri state =
    -- Note: This should be handled on the server side
    [ ( "error", error ), ( "description", description ), ( "uri", uri ), ( "state", state ) ]
        |> List.filterMap dropUseless
        |> GitHubAuthError


authErrorParser : UrlParser.Parser (Maybe String -> Maybe String -> Maybe String -> Maybe String -> a) a
authErrorParser =
    -- see https://developer.github.com/apps/managing-oauth-apps/troubleshooting-authorization-request-errors/
    s "auth" </> s "github" <?> stringParam "error" <?> stringParam "error_description" <?> stringParam "error_uri" <?> stringParam "state"


dropUseless : ( a, Maybe b ) -> Maybe ( a, b )
dropUseless ( key, maybeValue ) =
    case maybeValue of
        Just value ->
            Just ( key, value )

        Nothing ->
            Nothing



---- VIEW ----


view : Model -> Html Msg
view model =
    Html.div [ Attr.class "centered" ]
        [ Html.main_ [] <|
            case model.page of
                Question ->
                    question model

                GitHubAuth dbKey code state ->
                    -- this route is currently never displayed
                    question model

                GitHubAuthError errors ->
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
                    , Html.p [] [ Html.text location.pathname ]
                    ]
        , footer model
        ]


question : Model -> List (Html Msg)
question model =
    [ Html.h1 [] [ Html.text model.question ]
    , Html.label []
        [ Html.text "Answer "
        , Html.input
            [ onInput Answer
            , Attr.defaultValue <|
                Maybe.withDefault "" model.answer
            ]
            []
        ]
    , Html.hr [] []
    , Html.h2 [] [ Html.text "Email" ]
    , case model.email of
        NotAsked ->
            Html.button
                [ Attr.class "button github"
                , onClick GetGitHubUrl
                ]
                [ Html.text "Provide with Github" ]

        Received email ->
            Html.p [] [ Html.text email ]

        Checking ->
            Html.div [ Attr.class "loader" ] [ Html.text "Loading..." ]

        Failed error ->
            Html.code [] [ Html.text <| toString error ]
    ]


footer : Model -> Html msg
footer model =
    let
        page =
            case model.page of
                Question ->
                    "Question"

                Unknown location ->
                    "Unknown"

                GitHubAuth dbKey code state ->
                    "GitHub Authentication code received"

                GitHubAuthError _ ->
                    "GitHub Authentication failed"
    in
    Html.footer []
        [ Html.a [ Attr.href "/" ] [ Html.text "Start again" ]
        , Html.span [] [ Html.text <| "Page: " ++ page ]
        ]



---- PROGRAM ----


main : Program Json.Decode.Value Model Msg
main =
    Navigation.programWithFlags UrlChange
        { view = view
        , init = init
        , update = update
        , subscriptions = always Sub.none
        }
