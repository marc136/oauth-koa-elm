module Api exposing (getAuthUrl, verifyMailGitHub, verifyMailGoogle)

import Http
import Json.Decode
import Json.Encode


getAuthUrl : String -> (Result Http.Error String -> msg) -> { a | question : String, answer : Maybe String } -> Cmd msg
getAuthUrl provider msg { question, answer } =
    Http.send msg <|
        Http.request
            { method = "POST"
            , headers = []
            , url = "/auth/" ++ provider ++ "/get-url"
            , body =
                [ ( "question", Json.Encode.string question )
                , ( "answer", Json.Encode.string (Maybe.withDefault "" answer) )
                ]
                    |> Json.Encode.object
                    |> Http.jsonBody
            , expect = Http.expectString
            , timeout = Nothing
            , withCredentials = False
            }


verifyMailGitHub : (Result Http.Error String -> msg) -> String -> String -> String -> Cmd msg
verifyMailGitHub msg dbKey code state =
    Http.send msg <|
        Http.post ("/auth/github/" ++ dbKey)
            ([ ( "code", Json.Encode.string code )
             , ( "state", Json.Encode.string state )
             ]
                |> Json.Encode.object
                |> Http.jsonBody
            )
            decodeEmail


verifyMailGoogle : (Result Http.Error String -> msg) -> String -> String -> Cmd msg
verifyMailGoogle msg dbKey code =
    Http.send msg <|
        Http.post ("/auth/google/" ++ dbKey)
            ([ ( "code", Json.Encode.string code ) ]
                |> Json.Encode.object
                |> Http.jsonBody
            )
            decodeEmail


decodeEmail : Json.Decode.Decoder String
decodeEmail =
    Json.Decode.field "email" Json.Decode.string
