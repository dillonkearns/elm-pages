module Page.TailwindForm exposing (Data, Model, Msg, page)

import Css
import Css.Global
import DataSource exposing (DataSource)
import Dict exposing (Dict)
import Form exposing (Form)
import Head
import Head.Seo as Seo
import Html.Styled as Html exposing (Html)
import Html.Styled.Attributes as Attr exposing (css)
import Icon
import Page exposing (Page, PageWithState, StaticPayload)
import PageServerResponse exposing (PageServerResponse)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Server.Request as Request exposing (Request)
import Shared
import Tailwind.Breakpoints as Bp
import Tailwind.Utilities as Tw
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
    , birthDay : String
    }


defaultUser : User
defaultUser =
    { first = "Jane"
    , last = "Doe"
    , username = "janedoe"
    , email = "janedoe@example.com"
    , birthDay = "1969-07-20"
    }


errorsView : List String -> Html.Html msg
errorsView errors =
    case errors of
        first :: rest ->
            Html.div []
                [ Html.ul
                    [ Attr.style "border" "solid red"
                    ]
                    (List.map
                        (\error ->
                            Html.li []
                                [ Html.text error
                                ]
                        )
                        (first :: rest)
                    )
                ]

        [] ->
            Html.div [] []


styleAttrs attrs =
    List.map Attr.fromUnstyled attrs



--usernameInput : Html msg


usernameInput { toInput, toLabel, errors } =
    Html.div []
        [ Html.div
            [ css
                [ Bp.sm
                    [ Tw.grid
                    , Tw.grid_cols_3
                    , Tw.gap_4
                    , Tw.items_start
                    , Tw.border_t
                    , Tw.border_gray_200
                    , Tw.pt_5
                    ]
                ]
            ]
            [ Html.label
                (styleAttrs toInput
                    ++ [ Attr.for "username"
                       , css
                            [ Tw.block
                            , Tw.text_sm
                            , Tw.font_medium
                            , Tw.text_gray_700
                            , Bp.sm
                                [ Tw.mt_px
                                , Tw.pt_2
                                ]
                            ]
                       ]
                )
                [ Html.text "Username" ]
            , Html.div
                [ css
                    [ Tw.mt_1
                    , Bp.sm
                        [ Tw.mt_0
                        , Tw.col_span_2
                        ]
                    ]
                ]
                [ Html.div
                    [ css
                        [ Tw.max_w_lg
                        , Tw.flex
                        , Tw.rounded_md
                        , Tw.shadow_sm
                        , Tw.relative
                        ]
                    ]
                    [ Html.span
                        [ css
                            [ Tw.inline_flex
                            , Tw.items_center
                            , Tw.px_3
                            , Tw.rounded_l_md
                            , Tw.border
                            , Tw.border_r_0
                            , Tw.border_gray_300
                            , Tw.bg_gray_50
                            , Tw.text_gray_500
                            , Bp.sm
                                [ Tw.text_sm
                                ]
                            ]
                        ]
                        [ Html.text "workcation.com/" ]
                    , Html.input
                        (styleAttrs toInput
                            ++ [ Attr.type_ "text"
                               , Attr.name "username"
                               , Attr.id "username"
                               , Attr.attribute "autocomplete" "username"
                               , css
                                    [ Tw.flex_1
                                    , Tw.block
                                    , Tw.w_full
                                    , Tw.min_w_0
                                    , Tw.rounded_none
                                    , Tw.rounded_r_md
                                    , Tw.border_gray_300
                                    , Css.focus
                                        [ Tw.ring_indigo_500
                                        , Tw.border_indigo_500
                                        ]
                                    , Bp.sm
                                        [ Tw.text_sm
                                        ]
                                    ]
                               ]
                        )
                        []
                    , Html.div
                        [ css
                            [ Tw.absolute
                            , Tw.inset_y_0
                            , Tw.right_0
                            , Tw.pr_3
                            , Tw.flex
                            , Tw.items_center
                            , Tw.pointer_events_none
                            ]
                        ]
                        [ if errors |> List.isEmpty then
                            Html.text ""

                          else
                            Icon.error
                        ]
                    ]
                ]
            ]
        , Html.div []
            [ Html.p
                [ css
                    [ Tw.mt_2
                    , Tw.text_sm
                    , Tw.text_red_600
                    ]
                ]
                [ errors |> String.join "\n" |> Html.text ]
            ]
        ]


inputWithErrors =
    Html.div []
        [ Html.label
            [ Attr.for "email"
            , css
                [ Tw.block
                , Tw.text_sm
                , Tw.font_medium
                , Tw.text_gray_700
                ]
            ]
            [ Html.text "Email" ]
        , Html.div
            [ css
                [ Tw.mt_1
                , Tw.relative
                , Tw.rounded_md
                , Tw.shadow_sm
                ]
            ]
            [ Html.input
                [ Attr.type_ "email"
                , Attr.name "email"
                , Attr.id "email"
                , css
                    [ Tw.block
                    , Tw.w_full
                    , Tw.pr_10
                    , Tw.border_red_300
                    , Tw.text_red_900
                    , Tw.placeholder_red_300
                    , Tw.rounded_md
                    , Css.focus
                        [ Tw.outline_none
                        , Tw.ring_red_500
                        , Tw.border_red_500
                        ]
                    , Bp.sm
                        [ Tw.text_sm
                        ]
                    ]
                , Attr.placeholder "you@example.com"
                , Attr.value "adamwathan"
                , Attr.attribute "aria-invalid" "true"
                , Attr.attribute "aria-describedby" "email-error"
                ]
                []
            , Html.div
                [ css
                    [ Tw.absolute
                    , Tw.inset_y_0
                    , Tw.right_0
                    , Tw.pr_3
                    , Tw.flex
                    , Tw.items_center
                    , Tw.pointer_events_none
                    ]
                ]
                [ Icon.error
                ]
            ]
        , Html.div []
            [ Html.p
                [ css
                    [ Tw.mt_2
                    , Tw.text_sm
                    , Tw.text_red_600
                    ]
                , Attr.id "email-error"
                ]
                [ Html.text "Your password must be less than 4 characters." ]
            ]
        ]


form : User -> Form User (Html Never)
form user =
    Form.succeed User
        |> Form.required
            (Form.input
                "first"
                (\{ toInput, toLabel, errors } ->
                    Html.div []
                        [ errorsView errors
                        , Html.label (styleAttrs toLabel)
                            [ Html.text "First"
                            ]
                        , Html.input (styleAttrs toInput) []
                        ]
                )
                |> Form.withInitialValue user.first
            )
        |> Form.required
            (Form.input
                "last"
                (\{ toInput, toLabel, errors } ->
                    Html.div []
                        [ errorsView errors
                        , Html.label (styleAttrs toLabel)
                            [ Html.text "Last"
                            ]
                        , Html.input (styleAttrs toInput) []
                        ]
                )
                |> Form.withInitialValue user.last
            )
        |> Form.required
            (Form.input "username" usernameInput
                |> Form.withInitialValue user.username
                |> Form.withServerValidation
                    (\username ->
                        if username == "asdf" then
                            DataSource.succeed [ "username is taken" ]

                        else
                            DataSource.succeed []
                    )
            )
        |> Form.required
            (Form.input
                "email"
                (\{ toInput, toLabel, errors } ->
                    Html.div []
                        [ errorsView errors
                        , Html.label (styleAttrs toLabel)
                            [ Html.text "Email"
                            ]
                        , Html.input (styleAttrs toInput) []
                        ]
                )
                |> Form.withInitialValue user.email
            )
        |> Form.required
            (Form.date
                "dob"
                (\{ toInput, toLabel, errors } ->
                    Html.div []
                        [ errorsView errors
                        , Html.label (styleAttrs toLabel)
                            [ Html.text "Date of Birth"
                            ]
                        , Html.input (styleAttrs toInput) []
                        ]
                )
                |> Form.withInitialValue user.birthDay
                |> Form.withMinDate "1900-01-01"
                |> Form.withMaxDate "2022-01-01"
            )
        |> Form.append
            (Form.submit
                (\{ attrs } ->
                    Html.button
                        (styleAttrs attrs
                            ++ [ css
                                    [ Tw.ml_3
                                    , Tw.inline_flex
                                    , Tw.justify_center
                                    , Tw.py_2
                                    , Tw.px_4
                                    , Tw.border
                                    , Tw.border_transparent
                                    , Tw.shadow_sm
                                    , Tw.text_sm
                                    , Tw.font_medium
                                    , Tw.rounded_md
                                    , Tw.text_white
                                    , Tw.bg_indigo_600
                                    , Css.focus
                                        [ Tw.outline_none
                                        , Tw.ring_2
                                        , Tw.ring_offset_2
                                        , Tw.ring_indigo_500
                                        ]
                                    , Css.hover
                                        [ Tw.bg_indigo_700
                                        ]
                                    , Tw.cursor_pointer
                                    ]
                               ]
                        )
                        [ Html.text "Save" ]
                )
            )


page : Page RouteParams Data
page =
    Page.serverRender
        { head = head
        , data = data
        }
        |> Page.buildNoState { view = view }


type alias Data =
    { user : Maybe User
    , errors : Maybe (Dict String { raw : String, errors : List String })
    }


data : RouteParams -> Request (DataSource (PageServerResponse Data))
data routeParams =
    Request.oneOf
        [ Form.toRequest2 (form defaultUser)
            |> Request.map
                (\userOrErrors ->
                    userOrErrors
                        |> DataSource.map
                            (\result ->
                                (case result of
                                    Ok ( user, errors ) ->
                                        { user = Just user
                                        , errors = Just errors
                                        }

                                    Err errors ->
                                        { user = Nothing
                                        , errors = Just errors
                                        }
                                )
                                    |> PageServerResponse.RenderPage
                            )
                )
        , PageServerResponse.RenderPage
            { user = Nothing
            , errors = Nothing
            }
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
        user : User
        user =
            static.data.user
                |> Maybe.withDefault defaultUser
    in
    { title = "Form Example"
    , body =
        [ Html.div
            []
            [ Css.Global.global Tw.globalStyles
            , static.data.user
                |> Maybe.map
                    (\user_ ->
                        Html.p
                            [ css
                                [ Css.backgroundColor (Css.rgb 163 251 163)
                                , Tw.p_4
                                ]
                            ]
                            [ Html.text <| "Successfully received user " ++ user_.first ++ " " ++ user_.last
                            ]
                    )
                |> Maybe.withDefault (Html.p [] [])
            , Html.h1
                []
                [ Html.text <| "Edit profile " ++ user.first ++ " " ++ user.last ]
            , form user
                |> Form.toHtml
                    (\attrs children -> Html.form (List.map Attr.fromUnstyled attrs) children)
                    static.data.errors
            ]
            |> Html.toUnstyled
        ]
    }
