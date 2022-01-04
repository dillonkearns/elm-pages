module Page.TailwindForm exposing (Data, Model, Msg, page)

import Css
import Css.Global
import DataSource exposing (DataSource)
import Date exposing (Date)
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
import Time
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
    , birthDay : Date
    , checkbox : Bool
    }


defaultUser : User
defaultUser =
    { first = "Jane"
    , last = "Doe"
    , username = "janedoe"
    , email = "janedoe@example.com"
    , birthDay = Date.fromCalendarDate 1969 Time.Jul 20
    , checkbox = False
    }


styleAttrs attrs =
    List.map Attr.fromUnstyled attrs


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
        , Html.p
            [ css
                [ Tw.mt_2
                , Tw.text_sm
                , Tw.text_red_600
                ]
            ]
            [ errors |> String.join "\n" |> Html.text ]
        ]


form : User -> Form User (Html Never)
form user =
    Form.succeed User
        |> Form.required
            (Form.input
                "first"
                (textInput "First name")
                |> Form.withInitialValue user.first
            )
        |> Form.required
            (Form.input
                "last"
                (textInput "Last name")
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
                (textInput "Email address")
                |> Form.withInitialValue user.email
            )
        |> Form.required
            (Form.date
                "dob"
                (textInput "Date of Birth")
                |> Form.withInitialValue (user.birthDay |> Date.toIsoString)
                |> Form.withMinDate "1900-01-01"
                |> Form.withMaxDate "2022-01-01"
                |> Form.withServerValidation
                    (\birthDate ->
                        let
                            _ =
                                birthDate |> Date.toIsoString |> Debug.log "@@@date"
                        in
                        if (birthDate |> Debug.log "birthDate") == (Date.fromCalendarDate 1969 Time.Jul 20 |> Debug.log "rhs") then
                            DataSource.succeed [ "No way, that's when the moon landing happened!" ]

                        else
                            DataSource.succeed []
                    )
            )
        |> Form.required
            (Form.checkbox
                "checkbox"
                (\{ toInput, toLabel, errors } ->
                    Html.div []
                        [ --errorsView errors,
                          Html.label (styleAttrs toLabel)
                            [ Html.text "Checkbox"
                            ]
                        , Html.input (styleAttrs toInput) []
                        ]
                )
             --|> Form.withInitialValue user.checkbox
            )
        |> Form.wrap wrapSection
        |> Form.append
            (Form.submit
                (\{ attrs } ->
                    Html.div
                        [ css
                            [ Tw.pt_5
                            ]
                        ]
                        [ Html.div
                            [ css
                                [ Tw.flex
                                , Tw.justify_end
                                ]
                            ]
                            [ cancelButton
                            , saveButton attrs
                            ]
                        ]
                )
            )


saveButton formAttrs =
    Html.button
        (styleAttrs formAttrs
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
                    ]
               ]
        )
        [ Html.text "Save" ]


cancelButton : Html msg
cancelButton =
    Html.button
        [ Attr.type_ "button"
        , css
            [ Tw.bg_white
            , Tw.py_2
            , Tw.px_4
            , Tw.border
            , Tw.border_gray_300
            , Tw.rounded_md
            , Tw.shadow_sm
            , Tw.text_sm
            , Tw.font_medium
            , Tw.text_gray_700
            , Css.focus
                [ Tw.outline_none
                , Tw.ring_2
                , Tw.ring_offset_2
                , Tw.ring_indigo_500
                ]
            , Css.hover
                [ Tw.bg_gray_50
                ]
            ]
        ]
        [ Html.text "Cancel" ]


page : Page RouteParams Data
page =
    Page.serverRender
        { head = head
        , data = data
        }
        |> Page.buildNoState { view = view }


type alias Data =
    { user : Maybe User
    , errors : Maybe (Dict String { raw : Maybe String, errors : List String })
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


wrapSection : List (Html msg) -> Html msg
wrapSection children =
    Html.div []
        [ Html.div []
            [ Html.h3
                [ css
                    [ Tw.text_lg
                    , Tw.leading_6
                    , Tw.font_medium
                    , Tw.text_gray_900
                    ]
                ]
                [ Html.text "Profile" ]
            , Html.p
                [ css
                    [ Tw.mt_1
                    , Tw.max_w_2xl
                    , Tw.text_sm
                    , Tw.text_gray_500
                    ]
                ]
                [ Html.text "This information will be displayed publicly so be careful what you share." ]
            ]
        , Html.div
            [ css
                [ Tw.mt_6
                , Tw.space_y_6
                , Bp.sm
                    [ Tw.mt_5
                    , Tw.space_y_5
                    ]
                ]
            ]
            children
        ]


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

            --, Html.h1
            --    []
            --    [ Html.text <| "Edit profile " ++ user.first ++ " " ++ user.last ]
            , Html.div
                [ css
                    [ Tw.flex
                    , Tw.flex_col
                    , Tw.items_center
                    , Tw.mt_8
                    , Tw.border_gray_700
                    , Tw.rounded_lg
                    ]
                ]
                [ form user
                    |> Form.toHtml
                        (\attrs children -> Html.form (List.map Attr.fromUnstyled attrs) children)
                        static.data.errors
                ]

            --,
            --Html.div [
            --css [
            --                 Tw.flex
            --                , Tw.flex_col
            --                , Tw.items_center
            --                , Tw.mt_8
            --                , Tw.border_gray_700
            --                , Tw.rounded_lg
            --
            --
            --]
            --] [
            --fullView
            --]
            ]
            |> Html.toUnstyled
        ]
    }


textInput labelText { toInput, toLabel, errors } =
    Html.div
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
            ([ css
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
                ++ styleAttrs toLabel
            )
            [ Html.text labelText ]
        , Html.div
            [ css
                [ Tw.mt_1
                , Bp.sm
                    [ Tw.mt_0
                    , Tw.col_span_2
                    ]
                ]
            ]
            [ Html.input
                (styleAttrs toInput
                    ++ [ --Attr.attribute "autocomplete" "given-name",
                         css
                            [ Tw.max_w_lg
                            , Tw.block
                            , Tw.w_full
                            , Tw.shadow_sm
                            , Tw.border_gray_300
                            , Tw.rounded_md
                            , Css.focus
                                [ Tw.ring_indigo_500
                                , Tw.border_indigo_500
                                ]
                            , Bp.sm
                                [ Tw.max_w_xs
                                , Tw.text_sm
                                ]
                            ]
                       ]
                )
                []
            ]
        , Html.p
            [ css
                [ Tw.mt_2
                , Tw.text_sm
                , Tw.text_red_600
                ]
            ]
            [ errors |> String.join "\n" |> Html.text ]
        ]


textInput2 =
    Html.div
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
            [ Attr.for "first-name"
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
            [ Html.text "First name" ]
        , Html.div
            [ css
                [ Tw.mt_1
                , Bp.sm
                    [ Tw.mt_0
                    , Tw.col_span_2
                    ]
                ]
            ]
            [ Html.input
                [ Attr.type_ "text"
                , Attr.name "first-name"
                , Attr.id "first-name"
                , Attr.attribute "autocomplete" "given-name"
                , css
                    [ Tw.max_w_lg
                    , Tw.block
                    , Tw.w_full
                    , Tw.shadow_sm
                    , Tw.border_gray_300
                    , Tw.rounded_md
                    , Css.focus
                        [ Tw.ring_indigo_500
                        , Tw.border_indigo_500
                        ]
                    , Bp.sm
                        [ Tw.max_w_xs
                        , Tw.text_sm
                        ]
                    ]
                ]
                []
            ]
        ]



--fullView : Html msg
--fullView =
--     Html.form
--            [ css
--                [ Tw.space_y_8
--                , Tw.divide_y
--                , Tw.divide_gray_200
--                , Tw.max_w_2xl
--                ]
--            ]
--            [ Html.div
--                [ css
--                    [ Tw.space_y_8
--                    , Tw.divide_y
--                    , Tw.divide_gray_200
--                    , Bp.sm
--                        [ Tw.space_y_5
--                        ]
--                    ]
--                ]
--                [ Html.div []
--                    [ Html.div []
--                        [ Html.h3
--                            [ css
--                                [ Tw.text_lg
--                                , Tw.leading_6
--                                , Tw.font_medium
--                                , Tw.text_gray_900
--                                ]
--                            ]
--                            [ Html.text "Profile" ]
--                        , Html.p
--                            [ css
--                                [ Tw.mt_1
--                                , Tw.max_w_2xl
--                                , Tw.text_sm
--                                , Tw.text_gray_500
--                                ]
--                            ]
--                            [ Html.text "This information will be displayed publicly so be careful what you share." ]
--                        ]
--                    , Html.div
--                        [ css
--                            [ Tw.mt_6
--                            , Tw.space_y_6
--                            , Bp.sm
--                                [ Tw.mt_5
--                                , Tw.space_y_5
--                                ]
--                            ]
--                        ]
--                        [ Html.div
--                            [ css
--                                [ Bp.sm
--                                    [ Tw.grid
--                                    , Tw.grid_cols_3
--                                    , Tw.gap_4
--                                    , Tw.items_start
--                                    , Tw.border_t
--                                    , Tw.border_gray_200
--                                    , Tw.pt_5
--                                    ]
--                                ]
--                            ]
--                            [ Html.label
--                                [ Attr.for "username"
--                                , css
--                                    [ Tw.block
--                                    , Tw.text_sm
--                                    , Tw.font_medium
--                                    , Tw.text_gray_700
--                                    , Bp.sm
--                                        [ Tw.mt_px
--                                        , Tw.pt_2
--                                        ]
--                                    ]
--                                ]
--                                [ Html.text "Username" ]
--                            , Html.div
--                                [ css
--                                    [ Tw.mt_1
--                                    , Bp.sm
--                                        [ Tw.mt_0
--                                        , Tw.col_span_2
--                                        ]
--                                    ]
--                                ]
--                                [ Html.div
--                                    [ css
--                                        [ Tw.max_w_lg
--                                        , Tw.flex
--                                        , Tw.rounded_md
--                                        , Tw.shadow_sm
--                                        ]
--                                    ]
--                                    [ Html.span
--                                        [ css
--                                            [ Tw.inline_flex
--                                            , Tw.items_center
--                                            , Tw.px_3
--                                            , Tw.rounded_l_md
--                                            , Tw.border
--                                            , Tw.border_r_0
--                                            , Tw.border_gray_300
--                                            , Tw.bg_gray_50
--                                            , Tw.text_gray_500
--                                            , Bp.sm
--                                                [ Tw.text_sm
--                                                ]
--                                            ]
--                                        ]
--                                        [ Html.text "workcation.com/" ]
--                                    , Html.input
--                                        [ Attr.type_ "text"
--                                        , Attr.name "username"
--                                        , Attr.id "username"
--                                        , Attr.attribute "autocomplete" "username"
--                                        , css
--                                            [ Tw.flex_1
--                                            , Tw.block
--                                            , Tw.w_full
--                                            , Tw.min_w_0
--                                            , Tw.rounded_none
--                                            , Tw.rounded_r_md
--                                            , Tw.border_gray_300
--                                            , Css.focus
--                                                [ Tw.ring_indigo_500
--                                                , Tw.border_indigo_500
--                                                ]
--                                            , Bp.sm
--                                                [ Tw.text_sm
--                                                ]
--                                            ]
--                                        ]
--                                        []
--                                    ]
--                                ]
--                            ]
--                        , Html.div
--                            [ css
--                                [ Bp.sm
--                                    [ Tw.grid
--                                    , Tw.grid_cols_3
--                                    , Tw.gap_4
--                                    , Tw.items_start
--                                    , Tw.border_t
--                                    , Tw.border_gray_200
--                                    , Tw.pt_5
--                                    ]
--                                ]
--                            ]
--                            [ Html.label
--                                [ Attr.for "about"
--                                , css
--                                    [ Tw.block
--                                    , Tw.text_sm
--                                    , Tw.font_medium
--                                    , Tw.text_gray_700
--                                    , Bp.sm
--                                        [ Tw.mt_px
--                                        , Tw.pt_2
--                                        ]
--                                    ]
--                                ]
--                                [ Html.text "About" ]
--                            , Html.div
--                                [ css
--                                    [ Tw.mt_1
--                                    , Bp.sm
--                                        [ Tw.mt_0
--                                        , Tw.col_span_2
--                                        ]
--                                    ]
--                                ]
--                                [ Html.textarea
--                                    [ Attr.id "about"
--                                    , Attr.name "about"
--                                    , Attr.rows 3
--                                    , css
--                                        [ Tw.max_w_lg
--                                        , Tw.shadow_sm
--                                        , Tw.block
--                                        , Tw.w_full
--                                        , Tw.border
--                                        , Tw.border_gray_300
--                                        , Tw.rounded_md
--                                        , Css.focus
--                                            [ Tw.ring_indigo_500
--                                            , Tw.border_indigo_500
--                                            ]
--                                        , Bp.sm
--                                            [ Tw.text_sm
--                                            ]
--                                        ]
--                                    ]
--                                    []
--                                , Html.p
--                                    [ css
--                                        [ Tw.mt_2
--                                        , Tw.text_sm
--                                        , Tw.text_gray_500
--                                        ]
--                                    ]
--                                    [ Html.text "Write a few sentences about yourself." ]
--                                ]
--                            ]
--                        , Html.div
--                            [ css
--                                [ Bp.sm
--                                    [ Tw.grid
--                                    , Tw.grid_cols_3
--                                    , Tw.gap_4
--                                    , Tw.items_center
--                                    , Tw.border_t
--                                    , Tw.border_gray_200
--                                    , Tw.pt_5
--                                    ]
--                                ]
--                            ]
--                            [ Html.label
--                                [ Attr.for "photo"
--                                , css
--                                    [ Tw.block
--                                    , Tw.text_sm
--                                    , Tw.font_medium
--                                    , Tw.text_gray_700
--                                    ]
--                                ]
--                                [ Html.text "Photo" ]
--                            , Html.div
--                                [ css
--                                    [ Tw.mt_1
--                                    , Bp.sm
--                                        [ Tw.mt_0
--                                        , Tw.col_span_2
--                                        ]
--                                    ]
--                                ]
--                                [ Html.div
--                                    [ css
--                                        [ Tw.flex
--                                        , Tw.items_center
--                                        ]
--                                    ]
--                                    [ Html.span
--                                        [ css
--                                            [ Tw.h_12
--                                            , Tw.w_12
--                                            , Tw.rounded_full
--                                            , Tw.overflow_hidden
--                                            , Tw.bg_gray_100
--                                            ]
--                                        ]
--                                        [ Icon.icon2
--                                        ]
--                                    , Html.button
--                                        [ Attr.type_ "button"
--                                        , css
--                                            [ Tw.ml_5
--                                            , Tw.bg_white
--                                            , Tw.py_2
--                                            , Tw.px_3
--                                            , Tw.border
--                                            , Tw.border_gray_300
--                                            , Tw.rounded_md
--                                            , Tw.shadow_sm
--                                            , Tw.text_sm
--                                            , Tw.leading_4
--                                            , Tw.font_medium
--                                            , Tw.text_gray_700
--                                            , Css.focus
--                                                [ Tw.outline_none
--                                                , Tw.ring_2
--                                                , Tw.ring_offset_2
--                                                , Tw.ring_indigo_500
--                                                ]
--                                            , Css.hover
--                                                [ Tw.bg_gray_50
--                                                ]
--                                            ]
--                                        ]
--                                        [ Html.text "Change" ]
--                                    ]
--                                ]
--                            ]
--
--                        ]
--                    ]
--                , Html.div
--                    [ css
--                        [ Tw.pt_8
--                        , Tw.space_y_6
--                        , Bp.sm
--                            [ Tw.pt_10
--                            , Tw.space_y_5
--                            ]
--                        ]
--                    ]
--                    [ Html.div []
--                        [ Html.h3
--                            [ css
--                                [ Tw.text_lg
--                                , Tw.leading_6
--                                , Tw.font_medium
--                                , Tw.text_gray_900
--                                ]
--                            ]
--                            [ Html.text "Personal Information" ]
--                        , Html.p
--                            [ css
--                                [ Tw.mt_1
--                                , Tw.max_w_2xl
--                                , Tw.text_sm
--                                , Tw.text_gray_500
--                                ]
--                            ]
--                            [ Html.text "Use a permanent address where you can receive mail." ]
--                        ]
--                    , Html.div
--                        [ css
--                            [ Tw.space_y_6
--                            , Bp.sm
--                                [ Tw.space_y_5
--                                ]
--                            ]
--                        ]
--                        [ Html.div
--                            [ css
--                                [ Bp.sm
--                                    [ Tw.grid
--                                    , Tw.grid_cols_3
--                                    , Tw.gap_4
--                                    , Tw.items_start
--                                    , Tw.border_t
--                                    , Tw.border_gray_200
--                                    , Tw.pt_5
--                                    ]
--                                ]
--                            ]
--                            [ Html.label
--                                [ Attr.for "first-name"
--                                , css
--                                    [ Tw.block
--                                    , Tw.text_sm
--                                    , Tw.font_medium
--                                    , Tw.text_gray_700
--                                    , Bp.sm
--                                        [ Tw.mt_px
--                                        , Tw.pt_2
--                                        ]
--                                    ]
--                                ]
--                                [ Html.text "First name" ]
--                            , Html.div
--                                [ css
--                                    [ Tw.mt_1
--                                    , Bp.sm
--                                        [ Tw.mt_0
--                                        , Tw.col_span_2
--                                        ]
--                                    ]
--                                ]
--                                [ Html.input
--                                    [ Attr.type_ "text"
--                                    , Attr.name "first-name"
--                                    , Attr.id "first-name"
--                                    , Attr.attribute "autocomplete" "given-name"
--                                    , css
--                                        [ Tw.max_w_lg
--                                        , Tw.block
--                                        , Tw.w_full
--                                        , Tw.shadow_sm
--                                        , Tw.border_gray_300
--                                        , Tw.rounded_md
--                                        , Css.focus
--                                            [ Tw.ring_indigo_500
--                                            , Tw.border_indigo_500
--                                            ]
--                                        , Bp.sm
--                                            [ Tw.max_w_xs
--                                            , Tw.text_sm
--                                            ]
--                                        ]
--                                    ]
--                                    []
--                                ]
--                            ]
--                        , Html.div
--                            [ css
--                                [ Bp.sm
--                                    [ Tw.grid
--                                    , Tw.grid_cols_3
--                                    , Tw.gap_4
--                                    , Tw.items_start
--                                    , Tw.border_t
--                                    , Tw.border_gray_200
--                                    , Tw.pt_5
--                                    ]
--                                ]
--                            ]
--                            [ Html.label
--                                [ Attr.for "last-name"
--                                , css
--                                    [ Tw.block
--                                    , Tw.text_sm
--                                    , Tw.font_medium
--                                    , Tw.text_gray_700
--                                    , Bp.sm
--                                        [ Tw.mt_px
--                                        , Tw.pt_2
--                                        ]
--                                    ]
--                                ]
--                                [ Html.text "Last name" ]
--                            , Html.div
--                                [ css
--                                    [ Tw.mt_1
--                                    , Bp.sm
--                                        [ Tw.mt_0
--                                        , Tw.col_span_2
--                                        ]
--                                    ]
--                                ]
--                                [ Html.input
--                                    [ Attr.type_ "text"
--                                    , Attr.name "last-name"
--                                    , Attr.id "last-name"
--                                    , Attr.attribute "autocomplete" "family-name"
--                                    , css
--                                        [ Tw.max_w_lg
--                                        , Tw.block
--                                        , Tw.w_full
--                                        , Tw.shadow_sm
--                                        , Tw.border_gray_300
--                                        , Tw.rounded_md
--                                        , Css.focus
--                                            [ Tw.ring_indigo_500
--                                            , Tw.border_indigo_500
--                                            ]
--                                        , Bp.sm
--                                            [ Tw.max_w_xs
--                                            , Tw.text_sm
--                                            ]
--                                        ]
--                                    ]
--                                    []
--                                ]
--                            ]
--                        , Html.div
--                            [ css
--                                [ Bp.sm
--                                    [ Tw.grid
--                                    , Tw.grid_cols_3
--                                    , Tw.gap_4
--                                    , Tw.items_start
--                                    , Tw.border_t
--                                    , Tw.border_gray_200
--                                    , Tw.pt_5
--                                    ]
--                                ]
--                            ]
--                            [ Html.label
--                                [ Attr.for "email"
--                                , css
--                                    [ Tw.block
--                                    , Tw.text_sm
--                                    , Tw.font_medium
--                                    , Tw.text_gray_700
--                                    , Bp.sm
--                                        [ Tw.mt_px
--                                        , Tw.pt_2
--                                        ]
--                                    ]
--                                ]
--                                [ Html.text "Email address" ]
--                            , Html.div
--                                [ css
--                                    [ Tw.mt_1
--                                    , Bp.sm
--                                        [ Tw.mt_0
--                                        , Tw.col_span_2
--                                        ]
--                                    ]
--                                ]
--                                [ Html.input
--                                    [ Attr.id "email"
--                                    , Attr.name "email"
--                                    , Attr.type_ "email"
--                                    , Attr.attribute "autocomplete" "email"
--                                    , css
--                                        [ Tw.block
--                                        , Tw.max_w_lg
--                                        , Tw.w_full
--                                        , Tw.shadow_sm
--                                        , Tw.border_gray_300
--                                        , Tw.rounded_md
--                                        , Css.focus
--                                            [ Tw.ring_indigo_500
--                                            , Tw.border_indigo_500
--                                            ]
--                                        , Bp.sm
--                                            [ Tw.text_sm
--                                            ]
--                                        ]
--                                    ]
--                                    []
--                                ]
--                            ]
--                        , Html.div
--                            [ css
--                                [ Bp.sm
--                                    [ Tw.grid
--                                    , Tw.grid_cols_3
--                                    , Tw.gap_4
--                                    , Tw.items_start
--                                    , Tw.border_t
--                                    , Tw.border_gray_200
--                                    , Tw.pt_5
--                                    ]
--                                ]
--                            ]
--                            [ Html.label
--                                [ Attr.for "country"
--                                , css
--                                    [ Tw.block
--                                    , Tw.text_sm
--                                    , Tw.font_medium
--                                    , Tw.text_gray_700
--                                    , Bp.sm
--                                        [ Tw.mt_px
--                                        , Tw.pt_2
--                                        ]
--                                    ]
--                                ]
--                                [ Html.text "Country" ]
--                            , Html.div
--                                [ css
--                                    [ Tw.mt_1
--                                    , Bp.sm
--                                        [ Tw.mt_0
--                                        , Tw.col_span_2
--                                        ]
--                                    ]
--                                ]
--                                [ Html.select
--                                    [ Attr.id "country"
--                                    , Attr.name "country"
--                                    , Attr.attribute "autocomplete" "country-name"
--                                    , css
--                                        [ Tw.max_w_lg
--                                        , Tw.block
--                                        , Tw.w_full
--                                        , Tw.shadow_sm
--                                        , Tw.border_gray_300
--                                        , Tw.rounded_md
--                                        , Css.focus
--                                            [ Tw.ring_indigo_500
--                                            , Tw.border_indigo_500
--                                            ]
--                                        , Bp.sm
--                                            [ Tw.max_w_xs
--                                            , Tw.text_sm
--                                            ]
--                                        ]
--                                    ]
--                                    [ Html.option []
--                                        [ Html.text "United States" ]
--                                    , Html.option []
--                                        [ Html.text "Canada" ]
--                                    , Html.option []
--                                        [ Html.text "Mexico" ]
--                                    ]
--                                ]
--                            ]
--                        , Html.div
--                            [ css
--                                [ Bp.sm
--                                    [ Tw.grid
--                                    , Tw.grid_cols_3
--                                    , Tw.gap_4
--                                    , Tw.items_start
--                                    , Tw.border_t
--                                    , Tw.border_gray_200
--                                    , Tw.pt_5
--                                    ]
--                                ]
--                            ]
--                            [ Html.label
--                                [ Attr.for "street-address"
--                                , css
--                                    [ Tw.block
--                                    , Tw.text_sm
--                                    , Tw.font_medium
--                                    , Tw.text_gray_700
--                                    , Bp.sm
--                                        [ Tw.mt_px
--                                        , Tw.pt_2
--                                        ]
--                                    ]
--                                ]
--                                [ Html.text "Street address" ]
--                            , Html.div
--                                [ css
--                                    [ Tw.mt_1
--                                    , Bp.sm
--                                        [ Tw.mt_0
--                                        , Tw.col_span_2
--                                        ]
--                                    ]
--                                ]
--                                [ Html.input
--                                    [ Attr.type_ "text"
--                                    , Attr.name "street-address"
--                                    , Attr.id "street-address"
--                                    , Attr.attribute "autocomplete" "street-address"
--                                    , css
--                                        [ Tw.block
--                                        , Tw.max_w_lg
--                                        , Tw.w_full
--                                        , Tw.shadow_sm
--                                        , Tw.border_gray_300
--                                        , Tw.rounded_md
--                                        , Css.focus
--                                            [ Tw.ring_indigo_500
--                                            , Tw.border_indigo_500
--                                            ]
--                                        , Bp.sm
--                                            [ Tw.text_sm
--                                            ]
--                                        ]
--                                    ]
--                                    []
--                                ]
--                            ]
--                        , Html.div
--                            [ css
--                                [ Bp.sm
--                                    [ Tw.grid
--                                    , Tw.grid_cols_3
--                                    , Tw.gap_4
--                                    , Tw.items_start
--                                    , Tw.border_t
--                                    , Tw.border_gray_200
--                                    , Tw.pt_5
--                                    ]
--                                ]
--                            ]
--                            [ Html.label
--                                [ Attr.for "city"
--                                , css
--                                    [ Tw.block
--                                    , Tw.text_sm
--                                    , Tw.font_medium
--                                    , Tw.text_gray_700
--                                    , Bp.sm
--                                        [ Tw.mt_px
--                                        , Tw.pt_2
--                                        ]
--                                    ]
--                                ]
--                                [ Html.text "City" ]
--                            , Html.div
--                                [ css
--                                    [ Tw.mt_1
--                                    , Bp.sm
--                                        [ Tw.mt_0
--                                        , Tw.col_span_2
--                                        ]
--                                    ]
--                                ]
--                                [ Html.input
--                                    [ Attr.type_ "text"
--                                    , Attr.name "city"
--                                    , Attr.id "city"
--                                    , Attr.attribute "autocomplete" "address-level2"
--                                    , css
--                                        [ Tw.max_w_lg
--                                        , Tw.block
--                                        , Tw.w_full
--                                        , Tw.shadow_sm
--                                        , Tw.border_gray_300
--                                        , Tw.rounded_md
--                                        , Css.focus
--                                            [ Tw.ring_indigo_500
--                                            , Tw.border_indigo_500
--                                            ]
--                                        , Bp.sm
--                                            [ Tw.max_w_xs
--                                            , Tw.text_sm
--                                            ]
--                                        ]
--                                    ]
--                                    []
--                                ]
--                            ]
--                        , Html.div
--                            [ css
--                                [ Bp.sm
--                                    [ Tw.grid
--                                    , Tw.grid_cols_3
--                                    , Tw.gap_4
--                                    , Tw.items_start
--                                    , Tw.border_t
--                                    , Tw.border_gray_200
--                                    , Tw.pt_5
--                                    ]
--                                ]
--                            ]
--                            [ Html.label
--                                [ Attr.for "region"
--                                , css
--                                    [ Tw.block
--                                    , Tw.text_sm
--                                    , Tw.font_medium
--                                    , Tw.text_gray_700
--                                    , Bp.sm
--                                        [ Tw.mt_px
--                                        , Tw.pt_2
--                                        ]
--                                    ]
--                                ]
--                                [ Html.text "State / Province" ]
--                            , Html.div
--                                [ css
--                                    [ Tw.mt_1
--                                    , Bp.sm
--                                        [ Tw.mt_0
--                                        , Tw.col_span_2
--                                        ]
--                                    ]
--                                ]
--                                [ Html.input
--                                    [ Attr.type_ "text"
--                                    , Attr.name "region"
--                                    , Attr.id "region"
--                                    , Attr.attribute "autocomplete" "address-level1"
--                                    , css
--                                        [ Tw.max_w_lg
--                                        , Tw.block
--                                        , Tw.w_full
--                                        , Tw.shadow_sm
--                                        , Tw.border_gray_300
--                                        , Tw.rounded_md
--                                        , Css.focus
--                                            [ Tw.ring_indigo_500
--                                            , Tw.border_indigo_500
--                                            ]
--                                        , Bp.sm
--                                            [ Tw.max_w_xs
--                                            , Tw.text_sm
--                                            ]
--                                        ]
--                                    ]
--                                    []
--                                ]
--                            ]
--                        , Html.div
--                            [ css
--                                [ Bp.sm
--                                    [ Tw.grid
--                                    , Tw.grid_cols_3
--                                    , Tw.gap_4
--                                    , Tw.items_start
--                                    , Tw.border_t
--                                    , Tw.border_gray_200
--                                    , Tw.pt_5
--                                    ]
--                                ]
--                            ]
--                            [ Html.label
--                                [ Attr.for "postal-code"
--                                , css
--                                    [ Tw.block
--                                    , Tw.text_sm
--                                    , Tw.font_medium
--                                    , Tw.text_gray_700
--                                    , Bp.sm
--                                        [ Tw.mt_px
--                                        , Tw.pt_2
--                                        ]
--                                    ]
--                                ]
--                                [ Html.text "ZIP / Postal code" ]
--                            , Html.div
--                                [ css
--                                    [ Tw.mt_1
--                                    , Bp.sm
--                                        [ Tw.mt_0
--                                        , Tw.col_span_2
--                                        ]
--                                    ]
--                                ]
--                                [ Html.input
--                                    [ Attr.type_ "text"
--                                    , Attr.name "postal-code"
--                                    , Attr.id "postal-code"
--                                    , Attr.attribute "autocomplete" "postal-code"
--                                    , css
--                                        [ Tw.max_w_lg
--                                        , Tw.block
--                                        , Tw.w_full
--                                        , Tw.shadow_sm
--                                        , Tw.border_gray_300
--                                        , Tw.rounded_md
--                                        , Css.focus
--                                            [ Tw.ring_indigo_500
--                                            , Tw.border_indigo_500
--                                            ]
--                                        , Bp.sm
--                                            [ Tw.max_w_xs
--                                            , Tw.text_sm
--                                            ]
--                                        ]
--                                    ]
--                                    []
--                                ]
--                            ]
--                        ]
--                    ]
--                , Html.div
--                    [ css
--                        [ Tw.divide_y
--                        , Tw.divide_gray_200
--                        , Tw.pt_8
--                        , Tw.space_y_6
--                        , Bp.sm
--                            [ Tw.pt_10
--                            , Tw.space_y_5
--                            ]
--                        ]
--                    ]
--                    [ Html.div []
--                        [ Html.h3
--                            [ css
--                                [ Tw.text_lg
--                                , Tw.leading_6
--                                , Tw.font_medium
--                                , Tw.text_gray_900
--                                ]
--                            ]
--                            [ Html.text "Notifications" ]
--                        , Html.p
--                            [ css
--                                [ Tw.mt_1
--                                , Tw.max_w_2xl
--                                , Tw.text_sm
--                                , Tw.text_gray_500
--                                ]
--                            ]
--                            [ Html.text "We'll always let you know about important changes, but you pick what else you want to hear about." ]
--                        ]
--                    , Html.div
--                        [ css
--                            [ Tw.space_y_6
--                            , Tw.divide_y
--                            , Tw.divide_gray_200
--                            , Bp.sm
--                                [ Tw.space_y_5
--                                ]
--                            ]
--                        ]
--                        [ Html.div
--                            [ css
--                                [ Tw.pt_6
--                                , Bp.sm
--                                    [ Tw.pt_5
--                                    ]
--                                ]
--                            ]
--                            [ Html.div
--                                [ Attr.attribute "role" "group"
--                                , Attr.attribute "aria-labelledby" "label-email"
--                                ]
--                                [ Html.div
--                                    [ css
--                                        [ Bp.sm
--                                            [ Tw.grid
--                                            , Tw.grid_cols_3
--                                            , Tw.gap_4
--                                            , Tw.items_baseline
--                                            ]
--                                        ]
--                                    ]
--                                    [ Html.div []
--                                        [ Html.div
--                                            [ css
--                                                [ Tw.text_base
--                                                , Tw.font_medium
--                                                , Tw.text_gray_900
--                                                , Bp.sm
--                                                    [ Tw.text_sm
--                                                    , Tw.text_gray_700
--                                                    ]
--                                                ]
--                                            , Attr.id "label-email"
--                                            ]
--                                            [ Html.text "By Email" ]
--                                        ]
--                                    , Html.div
--                                        [ css
--                                            [ Tw.mt_4
--                                            , Bp.sm
--                                                [ Tw.mt_0
--                                                , Tw.col_span_2
--                                                ]
--                                            ]
--                                        ]
--                                        [ Html.div
--                                            [ css
--                                                [ Tw.max_w_lg
--                                                , Tw.space_y_4
--                                                ]
--                                            ]
--                                            [ Html.div
--                                                [ css
--                                                    [ Tw.relative
--                                                    , Tw.flex
--                                                    , Tw.items_start
--                                                    ]
--                                                ]
--                                                [ Html.div
--                                                    [ css
--                                                        [ Tw.flex
--                                                        , Tw.items_center
--                                                        , Tw.h_5
--                                                        ]
--                                                    ]
--                                                    [ Html.input
--                                                        [ Attr.id "comments"
--                                                        , Attr.name "comments"
--                                                        , Attr.type_ "checkbox"
--                                                        , css
--                                                            [ Tw.h_4
--                                                            , Tw.w_4
--                                                            , Tw.text_indigo_600
--                                                            , Tw.border_gray_300
--                                                            , Tw.rounded
--                                                            , Css.focus
--                                                                [ Tw.ring_indigo_500
--                                                                ]
--                                                            ]
--                                                        ]
--                                                        []
--                                                    ]
--                                                , Html.div
--                                                    [ css
--                                                        [ Tw.ml_3
--                                                        , Tw.text_sm
--                                                        ]
--                                                    ]
--                                                    [ Html.label
--                                                        [ Attr.for "comments"
--                                                        , css
--                                                            [ Tw.font_medium
--                                                            , Tw.text_gray_700
--                                                            ]
--                                                        ]
--                                                        [ Html.text "Comments" ]
--                                                    , Html.p
--                                                        [ css
--                                                            [ Tw.text_gray_500
--                                                            ]
--                                                        ]
--                                                        [ Html.text "Get notified when someones posts a comment on a posting." ]
--                                                    ]
--                                                ]
--                                            , Html.div []
--                                                [ Html.div
--                                                    [ css
--                                                        [ Tw.relative
--                                                        , Tw.flex
--                                                        , Tw.items_start
--                                                        ]
--                                                    ]
--                                                    [ Html.div
--                                                        [ css
--                                                            [ Tw.flex
--                                                            , Tw.items_center
--                                                            , Tw.h_5
--                                                            ]
--                                                        ]
--                                                        [ Html.input
--                                                            [ Attr.id "candidates"
--                                                            , Attr.name "candidates"
--                                                            , Attr.type_ "checkbox"
--                                                            , css
--                                                                [ Tw.h_4
--                                                                , Tw.w_4
--                                                                , Tw.text_indigo_600
--                                                                , Tw.border_gray_300
--                                                                , Tw.rounded
--                                                                , Css.focus
--                                                                    [ Tw.ring_indigo_500
--                                                                    ]
--                                                                ]
--                                                            ]
--                                                            []
--                                                        ]
--                                                    , Html.div
--                                                        [ css
--                                                            [ Tw.ml_3
--                                                            , Tw.text_sm
--                                                            ]
--                                                        ]
--                                                        [ Html.label
--                                                            [ Attr.for "candidates"
--                                                            , css
--                                                                [ Tw.font_medium
--                                                                , Tw.text_gray_700
--                                                                ]
--                                                            ]
--                                                            [ Html.text "Candidates" ]
--                                                        , Html.p
--                                                            [ css
--                                                                [ Tw.text_gray_500
--                                                                ]
--                                                            ]
--                                                            [ Html.text "Get notified when a candidate applies for a job." ]
--                                                        ]
--                                                    ]
--                                                ]
--                                            , Html.div []
--                                                [ Html.div
--                                                    [ css
--                                                        [ Tw.relative
--                                                        , Tw.flex
--                                                        , Tw.items_start
--                                                        ]
--                                                    ]
--                                                    [ Html.div
--                                                        [ css
--                                                            [ Tw.flex
--                                                            , Tw.items_center
--                                                            , Tw.h_5
--                                                            ]
--                                                        ]
--                                                        [ Html.input
--                                                            [ Attr.id "offers"
--                                                            , Attr.name "offers"
--                                                            , Attr.type_ "checkbox"
--                                                            , css
--                                                                [ Tw.h_4
--                                                                , Tw.w_4
--                                                                , Tw.text_indigo_600
--                                                                , Tw.border_gray_300
--                                                                , Tw.rounded
--                                                                , Css.focus
--                                                                    [ Tw.ring_indigo_500
--                                                                    ]
--                                                                ]
--                                                            ]
--                                                            []
--                                                        ]
--                                                    , Html.div
--                                                        [ css
--                                                            [ Tw.ml_3
--                                                            , Tw.text_sm
--                                                            ]
--                                                        ]
--                                                        [ Html.label
--                                                            [ Attr.for "offers"
--                                                            , css
--                                                                [ Tw.font_medium
--                                                                , Tw.text_gray_700
--                                                                ]
--                                                            ]
--                                                            [ Html.text "Offers" ]
--                                                        , Html.p
--                                                            [ css
--                                                                [ Tw.text_gray_500
--                                                                ]
--                                                            ]
--                                                            [ Html.text "Get notified when a candidate accepts or rejects an offer." ]
--                                                        ]
--                                                    ]
--                                                ]
--                                            ]
--                                        ]
--                                    ]
--                                ]
--                            ]
--                        , Html.div
--                            [ css
--                                [ Tw.pt_6
--                                , Bp.sm
--                                    [ Tw.pt_5
--                                    ]
--                                ]
--                            ]
--                            [ Html.div
--                                [ Attr.attribute "role" "group"
--                                , Attr.attribute "aria-labelledby" "label-notifications"
--                                ]
--                                [ Html.div
--                                    [ css
--                                        [ Bp.sm
--                                            [ Tw.grid
--                                            , Tw.grid_cols_3
--                                            , Tw.gap_4
--                                            , Tw.items_baseline
--                                            ]
--                                        ]
--                                    ]
--                                    [ Html.div []
--                                        [ Html.div
--                                            [ css
--                                                [ Tw.text_base
--                                                , Tw.font_medium
--                                                , Tw.text_gray_900
--                                                , Bp.sm
--                                                    [ Tw.text_sm
--                                                    , Tw.text_gray_700
--                                                    ]
--                                                ]
--                                            , Attr.id "label-notifications"
--                                            ]
--                                            [ Html.text "Push Notifications" ]
--                                        ]
--                                    , Html.div
--                                        [ css
--                                            [ Bp.sm
--                                                [ Tw.col_span_2
--                                                ]
--                                            ]
--                                        ]
--                                        [ Html.div
--                                            [ css
--                                                [ Tw.max_w_lg
--                                                ]
--                                            ]
--                                            [ Html.p
--                                                [ css
--                                                    [ Tw.text_sm
--                                                    , Tw.text_gray_500
--                                                    ]
--                                                ]
--                                                [ Html.text "These are delivered via SMS to your mobile phone." ]
--                                            , Html.div
--                                                [ css
--                                                    [ Tw.mt_4
--                                                    , Tw.space_y_4
--                                                    ]
--                                                ]
--                                                [ Html.div
--                                                    [ css
--                                                        [ Tw.flex
--                                                        , Tw.items_center
--                                                        ]
--                                                    ]
--                                                    [ Html.input
--                                                        [ Attr.id "push-everything"
--                                                        , Attr.name "push-notifications"
--                                                        , Attr.type_ "radio"
--                                                        , css
--                                                            [ Tw.h_4
--                                                            , Tw.w_4
--                                                            , Tw.text_indigo_600
--                                                            , Tw.border_gray_300
--                                                            , Css.focus
--                                                                [ Tw.ring_indigo_500
--                                                                ]
--                                                            ]
--                                                        ]
--                                                        []
--                                                    , Html.label
--                                                        [ Attr.for "push-everything"
--                                                        , css
--                                                            [ Tw.ml_3
--                                                            , Tw.block
--                                                            , Tw.text_sm
--                                                            , Tw.font_medium
--                                                            , Tw.text_gray_700
--                                                            ]
--                                                        ]
--                                                        [ Html.text "Everything" ]
--                                                    ]
--                                                , Html.div
--                                                    [ css
--                                                        [ Tw.flex
--                                                        , Tw.items_center
--                                                        ]
--                                                    ]
--                                                    [ Html.input
--                                                        [ Attr.id "push-email"
--                                                        , Attr.name "push-notifications"
--                                                        , Attr.type_ "radio"
--                                                        , css
--                                                            [ Tw.h_4
--                                                            , Tw.w_4
--                                                            , Tw.text_indigo_600
--                                                            , Tw.border_gray_300
--                                                            , Css.focus
--                                                                [ Tw.ring_indigo_500
--                                                                ]
--                                                            ]
--                                                        ]
--                                                        []
--                                                    , Html.label
--                                                        [ Attr.for "push-email"
--                                                        , css
--                                                            [ Tw.ml_3
--                                                            , Tw.block
--                                                            , Tw.text_sm
--                                                            , Tw.font_medium
--                                                            , Tw.text_gray_700
--                                                            ]
--                                                        ]
--                                                        [ Html.text "Same as email" ]
--                                                    ]
--                                                , Html.div
--                                                    [ css
--                                                        [ Tw.flex
--                                                        , Tw.items_center
--                                                        ]
--                                                    ]
--                                                    [ Html.input
--                                                        [ Attr.id "push-nothing"
--                                                        , Attr.name "push-notifications"
--                                                        , Attr.type_ "radio"
--                                                        , css
--                                                            [ Tw.h_4
--                                                            , Tw.w_4
--                                                            , Tw.text_indigo_600
--                                                            , Tw.border_gray_300
--                                                            , Css.focus
--                                                                [ Tw.ring_indigo_500
--                                                                ]
--                                                            ]
--                                                        ]
--                                                        []
--                                                    , Html.label
--                                                        [ Attr.for "push-nothing"
--                                                        , css
--                                                            [ Tw.ml_3
--                                                            , Tw.block
--                                                            , Tw.text_sm
--                                                            , Tw.font_medium
--                                                            , Tw.text_gray_700
--                                                            ]
--                                                        ]
--                                                        [ Html.text "No push notifications" ]
--                                                    ]
--                                                ]
--                                            ]
--                                        ]
--                                    ]
--                                ]
--                            ]
--                        ]
--                    ]
--                ]
--            , Html.div
--                [ css
--                    [ Tw.pt_5
--                    ]
--                ]
--                [ Html.div
--                    [ css
--                        [ Tw.flex
--                        , Tw.justify_end
--                        ]
--                    ]
--                    [ Html.button
--                        [ Attr.type_ "button"
--                        , css
--                            [ Tw.bg_white
--                            , Tw.py_2
--                            , Tw.px_4
--                            , Tw.border
--                            , Tw.border_gray_300
--                            , Tw.rounded_md
--                            , Tw.shadow_sm
--                            , Tw.text_sm
--                            , Tw.font_medium
--                            , Tw.text_gray_700
--                            , Css.focus
--                                [ Tw.outline_none
--                                , Tw.ring_2
--                                , Tw.ring_offset_2
--                                , Tw.ring_indigo_500
--                                ]
--                            , Css.hover
--                                [ Tw.bg_gray_50
--                                ]
--                            ]
--                        ]
--                        [ Html.text "Cancel" ]
--                    , Html.button
--                        [ Attr.type_ "submit"
--                        , css
--                            [ Tw.ml_3
--                            , Tw.inline_flex
--                            , Tw.justify_center
--                            , Tw.py_2
--                            , Tw.px_4
--                            , Tw.border
--                            , Tw.border_transparent
--                            , Tw.shadow_sm
--                            , Tw.text_sm
--                            , Tw.font_medium
--                            , Tw.rounded_md
--                            , Tw.text_white
--                            , Tw.bg_indigo_600
--                            , Css.focus
--                                [ Tw.outline_none
--                                , Tw.ring_2
--                                , Tw.ring_offset_2
--                                , Tw.ring_indigo_500
--                                ]
--                            , Css.hover
--                                [ Tw.bg_indigo_700
--                                ]
--                            ]
--                        ]
--                        [ Html.text "Save" ]
--                    ]
--                ]
--            ]
