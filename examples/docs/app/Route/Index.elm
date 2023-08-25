module Route.Index exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import Css
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html.Styled as Html exposing (..)
import Html.Styled.Attributes as Attr exposing (css)
import Link
import Pages.Url
import PagesMsg exposing (PagesMsg)
import Route exposing (Route)
import RouteBuilder exposing (App, StatelessRoute)
import Shared
import SiteOld
import Svg.Styled exposing (path, svg)
import Svg.Styled.Attributes as SvgAttr
import Tailwind.Breakpoints as Bp
import Tailwind.Theme as Theme
import Tailwind.Utilities as Tw
import UrlPath
import View exposing (View)
import View.CodeTab as CodeTab


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


type alias Data =
    ()


type alias ActionData =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.single
        { head = head
        , data = data
        }
        |> RouteBuilder.buildNoState { view = view }


head :
    App Data ActionData RouteParams
    -> List Head.Tag
head app =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = [ "images", "icon-png.png" ] |> UrlPath.join |> Pages.Url.fromPath
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = SiteOld.tagline
        , locale = Nothing
        , title = "elm-pages - " ++ SiteOld.tagline
        }
        |> Seo.website


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view app shared =
    { title = "elm-pages - a statically typed site generator"
    , body =
        [ landingView |> Html.map PagesMsg.fromMsg
        ]
    }


data : BackendTask FatalError Data
data =
    BackendTask.succeed ()


landingView : Html Msg
landingView =
    div
        [ css
            [ Tw.relative
            , Tw.pt_16
            , Tw.pb_32
            , Tw.overflow_hidden
            ]
        ]
        [ div
            [ Attr.attribute "aria-hidden" "true"
            , css
                [ Tw.absolute
                , Tw.inset_x_0
                , Tw.top_0
                , Tw.h_48

                --, Tw.bg_gradient_to_b
                , Tw.bg_gradient_to_b
                , Tw.from_color Theme.gray_100
                ]
            ]
            []
        , firstSection
            { heading = "Pull in typed Elm data to your pages"
            , body = "Whether your data is coming from markdown files, APIs, a CMS, or all of the above, elm-pages lets you pull in just the data you need for a page. No loading spinners, no Msg or update logic, just define your data and use it in your view."
            , buttonText = "Check out the Docs"
            , buttonLink = Route.Docs__Section__ { section = Nothing }
            , svgIcon = "M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"
            , code =
                ( "app/Route/Repo/Name_.elm", """module Route.Repo.Name_ exposing (Data, Model, Msg, route)

type alias Data = Int
type alias RouteParams = { name : String }

route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.preRender
        { head = head
        , pages = pages
        , data = data
        }
        |> RouteBuilder.buildNoState { view = view }

pages : BackendTask error (List RouteParams)
pages =
    BackendTask.succeed [ { name = "elm-pages" } ]

data : RouteParams -> BackendTask FatalError Data
data routeParams =
    BackendTask.Http.getJson
        (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages")
        (Decode.field "stargazer_count" Decode.int)
    |> BackendTask.allowFatal

view :
    App Data ActionData RouteParams
    -> View Msg
view app =
    { title = app.routeParams.name
    , body =
        [ h1 [] [ text app.routeParams.name ]
        , p [] [ text ("Stars: " ++ String.fromInt app.data) ]
        ]
    }""" )
            }
        , firstSection
            { heading = "Combine data from multiple sources"
            , body = "Wherever the data came from, you can transform BackendTasks and combine multiple BackendTasks using the full power of Elm's type system."
            , buttonText = "Learn more about BackendTasks"
            , buttonLink = Route.Docs__Section__ { section = Just "data-sources" }
            , svgIcon = "M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"
            , code =
                ( "src/Project.elm", """type alias Project =
    { name : String
    , description : String
    , stars : Int
    }


all : BackendTask FatalError (List Project)
all =
    Glob.succeed
        (\\projectName filePath ->
            BackendTask.map3 Project
                (BackendTask.succeed projectName)
                (BackendTask.File.rawFile filePath BackendTask.File.body |> BackendTask.allowFatal)
                (stars projectName)
        )
        |> Glob.match (Glob.literal "projects/")
        |> Glob.capture Glob.wildcard
        |> Glob.match (Glob.literal ".txt")
        |> Glob.captureFilePath
        |> Glob.toBackendTask
        |> BackendTask.allowFatal
        |> BackendTask.resolve


stars : String -> BackendTask Int
stars repoName =
    Decode.field "stargazers_count" Decode.int
    |> BackendTask.Http.getJson ("https://api.github.com/repos/dillonkearns/" ++ repoName)
    |> BackendTask.allowFatal
""" )
            }
        , firstSection
            { heading = "SEO"
            , body = "Make sure your site previews look polished with the type-safe SEO API. `elm-pages build` pre-renders HTML for your pages. And your SEO tags get access to the page's BackendTasks."
            , buttonText = "Learn about the SEO API"
            , buttonLink = Route.Docs__Section__ { section = Nothing }
            , svgIcon = "M10 21h7a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v11m0 5l4.879-4.879m0 0a3 3 0 104.243-4.242 3 3 0 00-4.243 4.242z"
            , code =
                ( "app/Route/Blog/Slug_.elm", """head :
    App Data ActionData RouteParams
    -> List Head.Tag
head app =
    Seo.summaryLarge
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = app.data.image
            , alt = app.data.description
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = app.data.description
        , locale = Nothing
        , title = app.data.title
        }
        |> Seo.article
            { tags = []
            , section = Nothing
            , publishedTime = Just (Date.toIsoString app.data.published)
            , modifiedTime = Nothing
            , expirationTime = Nothing
            }
""" )
            }
        , firstSection
            { heading = "Full-Stack Elm"
            , body = "With server-rendered routes, you can seamlessly pull in user-specific data from your backend and hydrate it into a dynamic Elm application. No API layer required. You can access incoming HTTP requests from your server-rendered routes, and even use the Session API to manage key-value pairs through signed cookies."
            , buttonText = "Learn about server-rendered routes"
            , buttonLink = Route.Docs__Section__ { section = Nothing }
            , svgIcon = "M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375m16.5 0v3.75m-16.5-3.75v3.75m16.5 0v3.75C20.25 16.153 16.556 18 12 18s-8.25-1.847-8.25-4.125v-3.75m16.5 0c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125"
            , code =
                ( "app/Route/Feed.elm", """module Route.Feed exposing (ActionData, Data, Model, Msg, RouteParams, route)


type alias RouteParams = {}


type alias Data =
    { user : User
    , posts : List Post
    }


data :
    RouteParams
    -> Request
    -> BackendTask FatalError (Response Data ErrorPage)
data routeParams request =
    request
    |> withUserOrRedirect
        (\\user ->
            BackendTask.map (Data user)
            (BackendTask.Custom.run "getPosts"
                (Encode.string user.id)
                (Decode.list postDecoder)
                |> BackendTask.allowFatal
            )
                |> BackendTask.map Server.Response.render
        )

withUserOrRedirect :
    (User -> BackendTask FatalError (Response Data ErrorPage))
    -> Request
    -> BackendTask FatalError (Response Data ErrorPage)
withUserOrRedirect withUser request =
    request
        |> Session.withSession
            { name = "session"
            , secrets =
                BackendTask.Env.expect "SESSION_SECRET"
                    |> BackendTask.allowFatal
                    |> BackendTask.map List.singleton
            , options = Nothing
            }
            (session ->
                session
                    |> Session.get "sessionId"
                    |> Maybe.map getUserFromSession
                    |> Maybe.map (BackendTask.andThen withUser)
                    |> Maybe.withDefault (BackendTask.succeed (Route.redirectTo Route.Login))
                    |> BackendTask.map (Tuple.pair session)
            )

getUserFromSession : String -> BackendTask FatalError User
getUserFromSession sessionId =
    BackendTask.Custom.run "getUserFromSession"
        (Encode.string sessionId)
        userDecoder
        |> BackendTask.allowFatal


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> Model
    -> View (PagesMsg Msg)
view app shared model =
    { title = "Feed"
    , body =
        [ navbarView app.data.user
        , postsView app.data.posts
        ]
    }
""" )
            }
        , firstSection
            { heading = "Forms Without the Wiring"
            , body = "elm-pages uses progressively enhanced web standards. The Web has had a way to send data to backends for decades, no need to re-invent the wheel! Just modernize it with some progressive enhancement. You define your Form and validations declaratively, and elm-pages gives you client-side validations and state with no Model/init/update wiring whatsoever. You can even derive pending/optimistic UI from the in-flight form submissions (which elm-pages manages and exposes to you for free as well!)."
            , buttonText = "Learn about the Form API"
            , buttonLink = Route.Docs__Section__ { section = Nothing }
            , svgIcon = "M3.375 19.5h17.25m-17.25 0a1.125 1.125 0 01-1.125-1.125M3.375 19.5h7.5c.621 0 1.125-.504 1.125-1.125m-9.75 0V5.625m0 12.75v-1.5c0-.621.504-1.125 1.125-1.125m18.375 2.625V5.625m0 12.75c0 .621-.504 1.125-1.125 1.125m1.125-1.125v-1.5c0-.621-.504-1.125-1.125-1.125m0 3.75h-7.5A1.125 1.125 0 0112 18.375m9.75-12.75c0-.621-.504-1.125-1.125-1.125H3.375c-.621 0-1.125.504-1.125 1.125m19.5 0v1.5c0 .621-.504 1.125-1.125 1.125M2.25 5.625v1.5c0 .621.504 1.125 1.125 1.125m0 0h17.25m-17.25 0h7.5c.621 0 1.125.504 1.125 1.125M3.375 8.25c-.621 0-1.125.504-1.125 1.125v1.5c0 .621.504 1.125 1.125 1.125m17.25-3.75h-7.5c-.621 0-1.125.504-1.125 1.125m8.625-1.125c.621 0 1.125.504 1.125 1.125v1.5c0 .621-.504 1.125-1.125 1.125m-17.25 0h7.5m-7.5 0c-.621 0-1.125.504-1.125 1.125v1.5c0 .621.504 1.125 1.125 1.125M12 10.875v-1.5m0 1.5c0 .621-.504 1.125-1.125 1.125M12 10.875c0 .621.504 1.125 1.125 1.125m-2.25 0c.621 0 1.125.504 1.125 1.125M13.125 12h7.5m-7.5 0c-.621 0-1.125.504-1.125 1.125M20.625 12c.621 0 1.125.504 1.125 1.125v1.5c0 .621-.504 1.125-1.125 1.125m-17.25 0h7.5M12 14.625v-1.5m0 1.5c0 .621-.504 1.125-1.125 1.125M12 14.625c0 .621.504 1.125 1.125 1.125m-2.25 0c.621 0 1.125.504 1.125 1.125m0 1.5v-1.5m0 0c0-.621.504-1.125 1.125-1.125m0 0h7.5"
            , code =
                ( "app/Route/Signup.elm", """module Route.Signup exposing (ActionData, Data, Model, Msg, RouteParams, route)


type alias Data = {}
type alias RouteParams = {}
type alias ActionData = { errors : Form.Response String }


route : RouteBuilder.StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.serverRender { data = data, action = action, head = head }
        |> RouteBuilder.buildNoState { view = view }


type alias ActionData =
    { errors : Form.Response String }


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view app shared =
    { title = "Sign Up"
    , body =
        [ Html.h2 [] [ Html.text "Sign Up" ]
        -- client-side validation wiring is managed by the framework
        , Form.renderHtml "signup" [] (Just << .errors) app () signUpForm
        ]
    }


data :
    RouteParams
    -> Request
    -> BackendTask FatalError (Response Data ErrorPage)
data routeParams request =
    BackendTask.succeed (Response.render {})


head : RouteBuilder.App Data ActionData RouteParams -> List Head.Tag
head app =
    []


action :
    RouteParams
    -> Request
    -> BackendTask FatalError (Response ActionData ErrorPage)
action routeParams request =
    case request |> Request.formData formHandlers of
        Just ( response, parsedForm ) ->
            case parsedForm of
                Form.Valid (SignUp okForm) ->
                    BackendTask.Custom.run "createUser"
                        -- client-side validations run on the server, too,
                        -- so we know that the password and password-confirmation matched
                        (Encode.object
                            [ ( "username", Encode.string okForm.username )
                            , ( "password", Encode.string okForm.password )
                            ]
                        )
                        (Decode.succeed ())
                        |> BackendTask.allowFatal
                        |> BackendTask.map (\\() -> Response.render { errors = response })

                Form.Invalid _ _ ->
                    "Error!"
                        |> Pages.Script.log
                        |> BackendTask.map (\\() -> Response.render { errors = response })

        Nothing ->
            BackendTask.fail (FatalError.fromString "Expected form submission."


errorsView :
    Form.Errors String
    -> Validation.Field String parsed kind
    -> Html (PagesMsg Msg)
errorsView errors field =
    errors
        |> Form.errorsForField field
        |> List.map (\\error -> Html.li [ Html.Attributes.style "color" "red" ] [ Html.text error ])
        |> Html.ul []


signUpForm : Form.HtmlForm String SignUpForm input Msg
signUpForm =
    (\\username password passwordConfirmation ->
        { combine =
            Validation.succeed SignUpForm
                |> Validation.andMap username
                |> Validation.andMap
                    (Validation.map2
                        (\\passwordValue passwordConfirmationValue ->
                            if passwordValue == passwordConfirmationValue then
                                Validation.succeed passwordValue

                            else
                                Validation.fail "Must match password" passwordConfirmation
                        )
                        password
                        passwordConfirmation
                        |> Validation.andThen identity
                    )
        , view =
            \\formState ->
                let
                    fieldView label field =
                        Html.div []
                            [ Html.label
                                []
                                [ Html.text (label ++ " ")
                                , Form.FieldView.input [] field
                                , errorsView formState.errors field
                                ]
                            ]
                in
                [ fieldView "username" username
                , fieldView "Password" password
                , fieldView "Password Confirmation" passwordConfirmation
                , if formState.isTransitioning then
                    Html.button
                        [ Html.Attributes.disabled True ]
                        [ Html.text "Signing Up..." ]

                  else
                    Html.button [] [ Html.text "Sign Up" ]
                ]
        }
    )
        |> Form.init
        |> Form.hiddenKind ( "kind", "regular" ) "Expected kind."
        |> Form.field "username" (Field.text |> Field.required "Required")
        |> Form.field "password" (Field.text |> Field.password |> Field.required "Required")
        |> Form.field "password-confirmation" (Field.text |> Field.password |> Field.required "Required")


type Action
    = SignUp SignUpForm


type alias SignUpForm =
    { username : String, password : String }


formHandlers : Form.ServerForms String Action
formHandlers =
    Form.initCombined SignUp signUpForm
""" )
            }
        ]


firstSection :
    { heading : String
    , body : String
    , buttonLink : Route
    , buttonText : String
    , svgIcon : String
    , code : ( String, String )
    }
    -> Html Msg
firstSection info =
    div
        [ css
            [ Tw.relative
            ]
        ]
        [ div
            [ css
                [ Bp.lg
                    [ Tw.mx_auto
                    , Tw.max_w_4xl
                    , Tw.px_8
                    ]
                ]
            ]
            [ div
                [ css
                    [ Tw.px_4
                    , Tw.max_w_xl
                    , Tw.mx_auto
                    , Bp.lg
                        [ Tw.py_16
                        , Tw.max_w_none
                        , Tw.mx_0
                        , Tw.px_0
                        ]
                    , Bp.sm
                        [ Tw.px_6
                        ]
                    ]
                ]
                [ div []
                    [ div []
                        [ span
                            [ css
                                [ Tw.h_12
                                , Tw.w_12
                                , Tw.rounded_md
                                , Tw.flex
                                , Tw.items_center
                                , Tw.justify_center
                                , Tw.bg_gradient_to_r
                                , Tw.from_color Theme.blue_600
                                , Tw.to_color Theme.blue_700
                                ]
                            ]
                            [ svg
                                [ SvgAttr.css
                                    [ Tw.h_6
                                    , Tw.w_6
                                    , Tw.text_color Theme.white
                                    ]
                                , SvgAttr.fill "none"
                                , SvgAttr.viewBox "0 0 24 24"
                                , SvgAttr.stroke "currentColor"
                                , Attr.attribute "aria-hidden" "true"
                                ]
                                [ path
                                    [ SvgAttr.strokeLinecap "round"
                                    , SvgAttr.strokeLinejoin "round"
                                    , SvgAttr.strokeWidth "2"
                                    , SvgAttr.d info.svgIcon
                                    ]
                                    []
                                ]
                            ]
                        ]
                    , div
                        [ css
                            [ Tw.mt_6
                            ]
                        ]
                        [ h2
                            [ css
                                [ Tw.text_3xl
                                , Tw.font_extrabold
                                , Tw.tracking_tight
                                , Tw.text_color Theme.gray_900
                                ]
                            ]
                            [ text info.heading ]
                        , p
                            [ css
                                [ Tw.mt_4
                                , Tw.text_lg
                                , Tw.text_color Theme.gray_500
                                ]
                            ]
                            [ text info.body ]
                        , div
                            [ css
                                [ Tw.mt_6
                                ]
                            ]
                            [ Link.link info.buttonLink
                                [ css
                                    [ Tw.inline_flex
                                    , Tw.px_4
                                    , Tw.py_2
                                    , Tw.border
                                    , Tw.border_color Theme.transparent
                                    , Tw.text_base
                                    , Tw.font_medium
                                    , Tw.rounded_md
                                    , Tw.shadow_sm
                                    , Tw.text_color Theme.white
                                    , Tw.bg_gradient_to_r
                                    , Tw.from_color Theme.blue_600
                                    , Tw.to_color Theme.blue_700
                                    , Css.hover
                                        [ Tw.from_color Theme.blue_700
                                        , Tw.to_color Theme.blue_800
                                        ]
                                    ]
                                ]
                                [ text info.buttonText ]
                            ]
                        ]
                    ]
                ]
            , div
                [ css
                    [ Tw.mt_12
                    , Bp.lg
                        [ Tw.mt_0
                        ]
                    , Bp.sm
                        [ Tw.mt_16
                        ]
                    ]
                ]
                [ div
                    [ css
                        [ Tw.pl_4
                        , Tw.neg_mr_48
                        , Tw.pb_12
                        , Bp.lg
                            [ Tw.px_0
                            , Tw.m_0
                            , Tw.relative
                            , Tw.h_full
                            ]
                        , Bp.md
                            [ Tw.neg_mr_16
                            ]
                        , Bp.sm
                            [ Tw.pl_6
                            ]
                        ]
                    ]
                    [ CodeTab.view info.code
                    ]
                ]
            ]
        ]
