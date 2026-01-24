module Route.Index exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import BackendTask.Custom
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html
import Json.Decode as Decode
import Json.Encode as Encode
import Pages.Url
import PagesMsg exposing (PagesMsg)
import Post exposing (Post)
import Route
import RouteBuilder exposing (App, StatefulRoute, StatelessRoute)
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


type alias ActionData =
    {}


route : StatelessRoute RouteParams Data () ActionData
route =
    RouteBuilder.single
        { head = head
        , data = data
        }
        |> RouteBuilder.buildNoState { view = view }


type alias Data =
    { posts : List Post
    }


data : BackendTask FatalError Data
data =
    BackendTask.succeed Data
        |> BackendTask.andMap
            (BackendTask.Custom.run "posts"
                Encode.null
                (Decode.list Post.decoder)
                |> BackendTask.allowFatal
            )


head :
    App Data () ActionData RouteParams
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
        , title = "TODO title"
        }
        |> Seo.website


view :
    App Data () ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view app shared =
    { title = "Index page"
    , body =
        [ Html.h1 [] [ Html.text "Posts" ]
        , app.data.posts
            |> List.map postView
            |> Html.ul []
        ]
    }


postView : Post -> Html.Html msg
postView post =
    Html.li []
        [ Route.Admin__Slug_ { slug = post.slug }
            |> Route.link []
                [ Html.text post.title
                ]
        ]
