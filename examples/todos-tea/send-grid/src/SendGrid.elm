module SendGrid exposing (Email, Error(..), decodeBadStatus, encodeSendEmail, sendGridApiUrl, textEmail)

import EmailAddress exposing (EmailAddress)
import Json.Encode as Encode
import List.Nonempty exposing (Nonempty)
import String.Nonempty exposing (NonemptyString)


type alias Email =
    { subject : NonemptyString
    , to : Nonempty EmailAddress
    , content : NonemptyString
    , nameOfSender : String
    , emailAddressOfSender : EmailAddress
    }


type Error
    = BadUrl String
    | Timeout
    | NetworkError
    | BadStatus Int String


sendGridApiUrl : String
sendGridApiUrl =
    "https://api.sendgrid.com/v3/mail/send"


encodeSendEmail : Email -> Encode.Value
encodeSendEmail email =
    Encode.object
        [ ( "personalizations"
          , Encode.list
                (\addr ->
                    Encode.object
                        [ ( "to"
                          , Encode.list
                                (\a -> Encode.object [ ( "email", Encode.string (EmailAddress.toString a) ) ])
                                [ addr ]
                          )
                        ]
                )
                (List.Nonempty.toList email.to)
          )
        , ( "from"
          , Encode.object
                [ ( "email", Encode.string (EmailAddress.toString email.emailAddressOfSender) )
                , ( "name", Encode.string email.nameOfSender )
                ]
          )
        , ( "subject", Encode.string (String.Nonempty.toString email.subject) )
        , ( "content"
          , Encode.list identity
                [ Encode.object
                    [ ( "type", Encode.string "text/plain" )
                    , ( "value", Encode.string (String.Nonempty.toString email.content) )
                    ]
                ]
          )
        ]


decodeBadStatus : { a | statusCode : Int } -> String -> Error
decodeBadStatus metadata body =
    BadStatus metadata.statusCode body


textEmail :
    { subject : NonemptyString
    , to : Nonempty EmailAddress
    , content : NonemptyString
    , nameOfSender : String
    , emailAddressOfSender : EmailAddress
    }
    -> Email
textEmail config =
    config
