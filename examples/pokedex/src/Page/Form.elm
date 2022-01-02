module Page.Form exposing (Data, Model, Msg, page)

import DataSource exposing (DataSource)
import Form exposing (Form)
import Head
import Head.Seo as Seo
import Html
import Page exposing (Page, PageWithState, StaticPayload)
import PageServerResponse exposing (PageServerResponse)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Server.Request as Request exposing (Request)
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    Never


type alias RouteParams =
    {}


type alias User =
    { first : String
    , last : String
    , username : String
    , email : String
    , birthYear : String
    }


defaultUser : User
defaultUser =
    { first = "Jane"
    , last = "Doe"
    , username = "janedoe"
    , email = "janedoe@example.com"
    , birthYear = "1999"
    }


form : User -> Form User
form user =
    Form.succeed User
        |> Form.required
            (Form.input { name = "first", label = "First" }
                |> Form.withInitialValue user.first
            )
        |> Form.required
            (Form.input { name = "last", label = "Last" }
                |> Form.withInitialValue user.last
            )
        |> Form.required
            (Form.input { name = "username", label = "Username" }
                |> Form.withInitialValue user.username
            )
        |> Form.required
            (Form.input { name = "email", label = "Email" }
                |> Form.withInitialValue user.email
            )
        |> Form.required
            (Form.number { name = "birthYear", label = "Birth Year" }
                |> Form.withInitialValue user.birthYear
            )


page : Page RouteParams Data
page =
    Page.serverRender
        { head = head
        , data = data
        }
        |> Page.buildNoState { view = view }


type alias Data =
    { name : Maybe User
    }


data : RouteParams -> Request (DataSource (PageServerResponse Data))
data routeParams =
    Request.oneOf
        [ Form.toRequest (form defaultUser)
            |> Request.map
                (\name ->
                    { name = Just name }
                        |> PageServerResponse.RenderPage
                        |> DataSource.succeed
                )
        , PageServerResponse.RenderPage { name = Nothing }
            |> DataSource.succeed
            |> Request.succeed
        ]


head :
    StaticPayload Data RouteParams
    -> List Head.Tag
head static =
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
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data RouteParams
    -> View Msg
view maybeUrl sharedModel static =
    let
        user =
            static.data.name
                |> Maybe.withDefault defaultUser
    in
    { title = "Form Example"
    , body =
        [ Html.h1 [] [ Html.text <| "Edit profile " ++ user.first ++ " " ++ user.last ]
        , form user
            |> Form.toHtml
        ]
    }
