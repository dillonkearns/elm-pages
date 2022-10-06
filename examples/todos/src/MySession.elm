module MySession exposing (..)

import Codec
import DataSource exposing (DataSource)
import DataSource.Env as Env
import Route
import Server.Request exposing (Parser)
import Server.Response exposing (Response)
import Server.Session as Session
import Server.SetCookie as SetCookie


cookieOptions : SetCookie.Options
cookieOptions =
    SetCookie.initOptions
        |> SetCookie.withPath "/"
        |> SetCookie.withSameSite SetCookie.Lax


withSession :
    (request -> Result Session.NotLoadedReason Session.Session -> DataSource ( Session.Session, Response data errorPage ))
    -> Parser request
    -> Parser (DataSource (Response data errorPage))
withSession =
    Session.withSession
        { name = "mysession"
        , secrets = Env.expect "SESSION_SECRET" |> DataSource.map List.singleton
        , options = cookieOptions
        }


withSessionOrRedirect :
    (request -> Session.Session -> DataSource ( Session.Session, Response data errorPage ))
    -> Parser request
    -> Parser (DataSource (Response data errorPage))
withSessionOrRedirect toRequest handler =
    Session.withSession
        { name = "mysession"
        , secrets = Env.expect "SESSION_SECRET" |> DataSource.map List.singleton
        , options = cookieOptions
        }
        (\request sessionResult ->
            sessionResult
                |> Result.map (toRequest request)
                |> Result.withDefault
                    (DataSource.succeed
                        ( Session.empty
                        , Route.redirectTo Route.Login
                        )
                    )
        )
        handler


expectSessionOrRedirect :
    (request -> Session.Session -> DataSource ( Session.Session, Response data errorPage ))
    -> Parser request
    -> Parser (DataSource (Response data errorPage))
expectSessionOrRedirect toRequest handler =
    Session.withSession
        { name = "mysession"
        , secrets = Env.expect "SESSION_SECRET" |> DataSource.map List.singleton
        , options = cookieOptions
        }
        (\request sessionResult ->
            sessionResult
                |> Result.map (toRequest request)
                |> Result.withDefault
                    (DataSource.succeed
                        ( Session.empty
                        , Route.redirectTo Route.Login
                        )
                    )
        )
        handler


expectSessionDataOrRedirect :
    (Session.Session -> Maybe parsedSession)
    -> (parsedSession -> request -> Session.Session -> DataSource ( Session.Session, Response data errorPage ))
    -> Parser request
    -> Parser (DataSource (Response data errorPage))
expectSessionDataOrRedirect parseSessionData handler toRequest =
    toRequest
        |> expectSessionOrRedirect
            (\parsedRequest session ->
                case parseSessionData session of
                    Just parsedSession ->
                        handler parsedSession parsedRequest session

                    Nothing ->
                        DataSource.succeed
                            ( session
                            , Route.redirectTo Route.Login
                            )
            )


schema =
    { name = ( "name", Codec.string )
    , message = ( "message", Codec.string )
    , user =
        ( "user"
        , Codec.object User
            |> Codec.field "id" .id Codec.int
            |> Codec.buildObject
        )
    }


type alias User =
    { id : Int
    }
