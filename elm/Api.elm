module Api exposing (..)

import Http
import Json.Decode
import Json.Encode


getGitHubUrl : (Result Http.Error String -> msg) -> { a | question : String, answer : Maybe String } -> Cmd msg
getGitHubUrl msg { question, answer } =
    Http.send msg <|
        Http.request
            { method = "POST"
            , headers = []
            , url = "/auth/github/get-url"
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


decodeEmail : Json.Decode.Decoder String
decodeEmail =
    Json.Decode.field "email" Json.Decode.string
