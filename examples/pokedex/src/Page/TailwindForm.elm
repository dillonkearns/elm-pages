module Page.TailwindForm exposing (Data, Model, Msg, page)

import Css
import Css.Global
import DataSource exposing (DataSource)
import Date exposing (Date)
import Dict exposing (Dict)
import Form exposing (Form)
import Head
import Head.Seo as Seo
import Html as CoreHtml
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
    { form : Form.Model
    }


type Msg
    = FormMsg Form.Msg


type alias RouteParams =
    {}


type alias User =
    { first : String
    , last : String
    , username : String
    , email : String
    , birthDay : Date
    , rating : Int
    , notificationPreferences : NotificationPreferences
    }


type alias NotificationPreferences =
    { comments : Bool
    , candidates : Bool
    , offers : Bool
    , pushNotificationsSetting : Maybe PushNotificationsSetting
    }


defaultUser : User
defaultUser =
    { first = "Jane"
    , last = "Doe"
    , username = "janedoe"
    , email = "janedoe@example.com"
    , birthDay = Date.fromCalendarDate 1969 Time.Jul 20
    , rating = 5
    , notificationPreferences =
        { comments = False
        , candidates = False
        , offers = False
        , pushNotificationsSetting = Nothing
        }
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


form : User -> Form User (Html Form.Msg)
form user =
    Form.succeed User
        |> Form.with
            (Form.text
                "first"
                (textInput "First name")
                |> Form.withInitialValue user.first
                |> Form.required
            )
        |> Form.with
            (Form.text
                "last"
                (textInput "Last name")
                |> Form.withInitialValue user.last
                |> Form.required
            )
        |> Form.with
            (Form.text "username" usernameInput
                |> Form.withInitialValue user.username
                |> Form.withServerValidation
                    (\username ->
                        if username == "asdf" then
                            DataSource.succeed [ "username is taken" ]

                        else
                            DataSource.succeed []
                    )
            )
        |> Form.with
            (Form.text
                "email"
                (textInput "Email address")
                |> Form.withInitialValue user.email
                |> Form.email
                |> Form.required
            )
        |> Form.with
            (Form.date
                "dob"
                (textInput "Date of Birth")
                |> Form.withInitialValue (user.birthDay |> Date.toIsoString)
                |> Form.withMinDate (Date.fromCalendarDate 1900 Time.Jan 1)
                |> Form.withMaxDate (Date.fromCalendarDate 2022 Time.Jan 1)
                |> Form.withServerValidation
                    (\birthDate ->
                        let
                            _ =
                                birthDate |> Date.toIsoString
                        in
                        if birthDate == Date.fromCalendarDate 1969 Time.Jul 20 then
                            DataSource.succeed [ "No way, that's when the moon landing happened!" ]

                        else
                            DataSource.succeed []
                    )
            )
        |> Form.with
            (Form.requiredNumber
                "rating"
                (textInput "Rating")
                |> Form.withMin 1
                |> Form.withMax 5
                |> Form.range
            )
        |> Form.wrap wrapSection
        |> Form.appendForm (|>)
            ((Form.succeed NotificationPreferences
                |> Form.with
                    (Form.checkbox
                        "comments"
                        --user.checkbox
                        False
                        (checkboxInput { name = "Comments", description = "Get notified when someones posts a comment on a posting." })
                    )
                |> Form.with
                    (Form.checkbox
                        "candidates"
                        --user.checkbox
                        False
                        (checkboxInput { name = "Candidates", description = "Get notified when a candidate applies for a job." })
                    )
                |> Form.with
                    (Form.checkbox
                        "offers"
                        --user.checkbox
                        False
                        (checkboxInput { name = "Offers", description = "Get notified when a candidate accepts or rejects an offer." })
                    )
                |> Form.wrap wrapEmailSection
                |> Form.appendForm (|>)
                    (Form.succeed identity
                        |> Form.with
                            (Form.radio
                                "push-notifications"
                                ( ( "PushAll", PushAll )
                                , [ ( "PushEmail", PushEmail )
                                  , ( "PushNone", PushNone )
                                  ]
                                )
                                radioInput
                                wrapPushNotificationsSection
                            )
                    )
             )
                |> Form.wrap wrapNotificationsSections
            )
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


type PushNotificationsSetting
    = PushAll
    | PushEmail
    | PushNone


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


page : PageWithState RouteParams Data Model Msg
page =
    Page.serverRender
        { head = head
        , data = data
        }
        |> Page.buildWithLocalState
            { view = view
            , update = update
            , init = init
            , subscriptions = \_ _ _ _ _ -> Sub.none
            }


update _ _ _ _ msg model =
    case msg of
        FormMsg formMsg ->
            ( { model | form = model.form |> Form.update formMsg }, Cmd.none )


init _ _ static =
    ( { form = static.data.errors |> Maybe.withDefault Form.init }, Cmd.none )


type alias Data =
    { user : Maybe (Result String User)
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


formModelView formModel =
    formModel
        |> Debug.toString
        |> Html.text
        |> List.singleton
        |> Html.pre []


view :
    Maybe PageUrl
    -> Shared.Model
    -> Model
    -> StaticPayload Data RouteParams
    -> View Msg
view maybeUrl sharedModel model static =
    let
        user : User
        user =
            static.data.user
                |> Maybe.withDefault (Ok defaultUser)
                |> Result.withDefault defaultUser
    in
    { title = "Form Example"
    , body =
        [ Html.div
            []
            [ Css.Global.global Tw.globalStyles
            , formModelView model.form
            , static.data.user
                |> Maybe.map
                    (Result.map
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
                    )
                |> Maybe.withDefault (Err "")
                |> Result.withDefault (Html.p [] [])
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
                        model.form
                    |> Html.map FormMsg
                ]
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


checkboxInput { name, description } { toLabel, toInput, errors } =
    Html.div
        [ css
            [ Tw.max_w_lg
            , Tw.space_y_4
            ]
        ]
        [ Html.div
            [ css
                [ Tw.relative
                , Tw.flex
                , Tw.items_start
                ]
            ]
            [ Html.div
                [ css
                    [ Tw.flex
                    , Tw.items_center
                    , Tw.h_5
                    ]
                ]
                [ Html.input
                    (styleAttrs toInput
                        ++ [ css
                                [ Tw.h_4
                                , Tw.w_4
                                , Tw.text_indigo_600
                                , Tw.border_gray_300
                                , Tw.rounded
                                , Css.focus
                                    [ Tw.ring_indigo_500
                                    ]
                                ]
                           ]
                    )
                    []
                ]
            , Html.div
                [ css
                    [ Tw.ml_3
                    , Tw.text_sm
                    ]
                ]
                [ Html.label
                    (styleAttrs toLabel
                        ++ [ css
                                [ Tw.font_medium
                                , Tw.text_gray_700
                                ]
                           ]
                    )
                    [ Html.text name ]
                , Html.p
                    [ css
                        [ Tw.text_gray_500
                        ]
                    ]
                    [ Html.text description ]
                ]
            ]
        ]


wrapNotificationsSections children =
    Html.div
        [ css
            [ Tw.divide_y
            , Tw.divide_gray_200
            , Tw.pt_8
            , Tw.space_y_6
            , Bp.sm
                [ Tw.pt_10
                , Tw.space_y_5
                ]
            ]
        ]
        [ Html.div []
            [ Html.h3
                [ css
                    [ Tw.text_lg
                    , Tw.leading_6
                    , Tw.font_medium
                    , Tw.text_gray_900
                    ]
                ]
                [ Html.text "Notifications" ]
            , Html.p
                [ css
                    [ Tw.mt_1
                    , Tw.max_w_2xl
                    , Tw.text_sm
                    , Tw.text_gray_500
                    ]
                ]
                [ Html.text "We'll always let you know about important changes, but you pick what else you want to hear about." ]
            ]
        , Html.div
            [ css
                [ Tw.space_y_6
                , Tw.divide_y
                , Tw.divide_gray_200
                , Bp.sm
                    [ Tw.space_y_5
                    ]
                ]
            ]
            children
        ]


wrapEmailSection children =
    Html.div
        [ css
            [ Tw.pt_6
            , Bp.sm
                [ Tw.pt_5
                ]
            ]
        ]
        [ Html.div
            [ Attr.attribute "role" "group"
            , Attr.attribute "aria-labelledby" "label-email"
            ]
            [ Html.div
                [ css
                    [ Bp.sm
                        [ Tw.grid
                        , Tw.grid_cols_3
                        , Tw.gap_4
                        , Tw.items_baseline
                        ]
                    ]
                ]
                [ Html.div []
                    [ Html.div
                        [ css
                            [ Tw.text_base
                            , Tw.font_medium
                            , Tw.text_gray_900
                            , Bp.sm
                                [ Tw.text_sm
                                , Tw.text_gray_700
                                ]
                            ]
                        , Attr.id "label-email"
                        ]
                        [ Html.text "By Email" ]
                    ]
                , Html.div
                    [ css
                        [ Tw.mt_4
                        , Bp.sm
                            [ Tw.mt_0
                            , Tw.col_span_2
                            ]
                        ]
                    ]
                    [ Html.div
                        [ css
                            [ Tw.max_w_lg
                            , Tw.space_y_4
                            ]
                        ]
                        children
                    ]
                ]
            ]
        ]


radioInput item { toLabel, toInput, errors } =
    Html.div
        [ css
            [ Tw.flex
            , Tw.items_center
            ]
        ]
        [ Html.input
            (styleAttrs toInput
                ++ [ css
                        [ Tw.h_4
                        , Tw.w_4
                        , Tw.text_indigo_600
                        , Tw.border_gray_300
                        , Css.focus
                            [ Tw.ring_indigo_500
                            ]
                        ]
                   ]
            )
            []
        , Html.label
            (styleAttrs toLabel
                ++ [ css
                        [ Tw.ml_3
                        , Tw.block
                        , Tw.text_sm
                        , Tw.font_medium
                        , Tw.text_gray_700
                        ]
                   ]
            )
            [ (case item of
                PushAll ->
                    "Everything"

                PushEmail ->
                    "Same as email"

                PushNone ->
                    "No push notifications"
              )
                |> Html.text
            ]
        ]


wrapPushNotificationsSection children =
    Html.div
        [ css
            [ Tw.pt_6
            , Bp.sm
                [ Tw.pt_5
                ]
            ]
        ]
        [ Html.div
            [ Attr.attribute "role" "group"
            , Attr.attribute "aria-labelledby" "label-notifications"
            ]
            [ Html.div
                [ css
                    [ Bp.sm
                        [ Tw.grid
                        , Tw.grid_cols_3
                        , Tw.gap_4
                        , Tw.items_baseline
                        ]
                    ]
                ]
                [ Html.div []
                    [ Html.div
                        [ css
                            [ Tw.text_base
                            , Tw.font_medium
                            , Tw.text_gray_900
                            , Bp.sm
                                [ Tw.text_sm
                                , Tw.text_gray_700
                                ]
                            ]
                        , Attr.id "label-notifications"
                        ]
                        [ Html.text "Push Notifications" ]
                    ]
                , Html.div
                    [ css
                        [ Bp.sm
                            [ Tw.col_span_2
                            ]
                        ]
                    ]
                    [ Html.div
                        [ css
                            [ Tw.max_w_lg
                            ]
                        ]
                        [ Html.p
                            [ css
                                [ Tw.text_sm
                                , Tw.text_gray_500
                                ]
                            ]
                            [ Html.text "These are delivered via SMS to your mobile phone." ]
                        , Html.div
                            [ css
                                [ Tw.mt_4
                                , Tw.space_y_4
                                ]
                            ]
                            children
                        ]
                    ]
                ]
            ]
        ]
