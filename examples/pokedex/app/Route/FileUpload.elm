module Route.FileUpload exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html
import Html.Attributes as Attr
import Pages.Url
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatelessRoute)
import Server.Request as Request
import Server.Response
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = \_ -> Request.skip "No action."
        }
        |> RouteBuilder.buildNoState { view = view }


type alias Data =
    Maybe Request.File


type alias ActionData =
    {}


data : RouteParams -> Request.Parser (BackendTask FatalError (Server.Response.Response Data ErrorPage))
data routeParams =
    Request.oneOf
        [ Request.expectMultiPartFormPost
            (\{ field, optionalField, fileField } ->
                fileField "file"
            )
            |> Request.map
                (\file ->
                    BackendTask.succeed (Server.Response.render (Just file))
                )
        , Request.succeed
            (BackendTask.succeed (Server.Response.render Nothing))
        ]


head :
    App Data ActionData RouteParams
    -> List Head.Tag
head app =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = Pages.Url.external "TODO"
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "TODO"
        , locale = Nothing
        , title = "TODO title" -- metadata.title -- TODO
        }
        |> Seo.website


view :
    Shared.Model
    -> App Data ActionData RouteParams
    -> View (PagesMsg Msg)
view shared app =
    { title = "File Upload"
    , body =
        [ app.data
            |> Maybe.map
                (\file ->
                    Html.div []
                        [ Html.h1 [] [ Html.text "Got file" ]
                        , Html.p [] [ Html.text file.name ]
                        ]
                )
            |> Maybe.withDefault (Html.text "No file uploaded. Choose a file to get started.")
        , Html.form [ Attr.method "POST", Attr.enctype "multipart/form-data" ]
            [ Html.input
                [ Attr.type_ "file"
                , Attr.name "file"
                ]
                []
            , Html.input
                [ Attr.type_ "submit"
                ]
                []
            ]
        ]
    }
