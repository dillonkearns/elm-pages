module Route.TailwindForm exposing (ActionData, Data, Model, Msg, route)

import Browser.Dom
import Css exposing (Color)
import Css.Global
import DataSource exposing (DataSource)
import Date exposing (Date)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import Form exposing (Form)
import Form.Value
import Head
import Head.Seo as Seo
import Html.Styled as Html exposing (Html)
import Html.Styled.Attributes as Attr exposing (css)
import Http
import Icon
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
import Server.Request as Request exposing (Parser)
import Server.Response as Response exposing (Response)
import Shared
import Tailwind.Breakpoints as Bp
import Tailwind.Utilities as Tw
import Task
import Time
import Url exposing (Url)
import View exposing (View)


type alias Model =
    { form : Form.Model
    , flashMessage : Maybe (Result String String)
    }


type Msg
    = FormMsg Form.Msg
    | MovedToTop
    | OnAction ActionData


type alias RouteParams =
    {}


type alias User =
    { first : String
    , last : String
    , username : String
    , email : String
    , birthDay : Date
    , checkIn : Date
    , checkOut : Date
    , rating : Int
    , password : ( String, String )
    , notificationPreferences : NotificationPreferences
    }


type alias NotificationPreferences =
    { comments : Bool
    , candidates : Bool
    , offers : Bool
    , pushNotificationsSetting : PushNotificationsSetting
    }


defaultUser : User
defaultUser =
    { first = "jane"
    , last = "Doe"
    , username = "janedoe"
    , email = "janedoe@example.com"
    , birthDay = Date.fromCalendarDate 1969 Time.Jul 20
    , checkIn = Date.fromCalendarDate 2022 Time.Jan 11
    , checkOut = Date.fromCalendarDate 2022 Time.Jan 12
    , rating = 5
    , password = ( "", "" )
    , notificationPreferences =
        { comments = False
        , candidates = False
        , offers = False
        , pushNotificationsSetting = PushNone
        }
    }


styleAttrs attrs =
    List.map Attr.fromUnstyled attrs


usernameInput ({ toInput, toLabel, errors, submitStatus } as info) =
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
        , errorsView info
        ]


validateCapitalized : String -> Result String String
validateCapitalized string =
    if string |> String.toList |> List.head |> Maybe.withDefault 'a' |> Char.isUpper then
        Ok string

    else
        Err "Needs to be capitalized"


form : User -> Form Msg String User (Html Msg)
form user =
    Form.succeed User
        |> Form.with
            (Form.text
                "first"
                (textInput "First name")
                |> Form.required "Required"
                |> Form.withInitialValue (user.first |> Form.Value.string)
                |> Form.withClientValidation validateCapitalized
            )
        |> Form.with
            (Form.text
                "last"
                (textInput "Last name")
                |> Form.required "Required"
                |> Form.withInitialValue (user.last |> Form.Value.string)
                |> Form.withClientValidation validateCapitalized
            )
        |> Form.with
            (Form.text "username" usernameInput
                |> Form.withInitialValue (user.username |> Form.Value.string)
                |> Form.required "Required"
                |> Form.withServerValidation
                    (\username ->
                        if username == "asdf" then
                            DataSource.succeed [ "username is taken" ]

                        else
                            DataSource.succeed []
                    )
                |> Form.withRecoverableClientValidation
                    (\username ->
                        Ok
                            ( username
                            , if username |> String.contains "@" then
                                [ "Cannot contain @ symbol" ]

                              else
                                []
                            )
                    )
                |> Form.withRecoverableClientValidation
                    (\username ->
                        Ok
                            ( username
                            , if username |> String.contains "#" then
                                [ "Cannot contain # symbol" ]

                              else
                                []
                            )
                    )
                |> Form.withRecoverableClientValidation
                    (\username ->
                        Ok
                            ( username
                            , if (username |> String.length) < 3 then
                                [ "Must be at least 3 characters long" ]

                              else
                                []
                            )
                    )
            )
        |> Form.with
            (Form.text
                "email"
                (textInput "Email address")
                |> Form.withInitialValue (user.email |> Form.Value.string)
                |> Form.email
                |> Form.required "Required"
            )
        |> Form.with
            (Form.date
                "dob"
                { invalid = \_ -> "Invalid date"
                }
                (textInput "Date of Birth")
                |> Form.required "Required"
                |> Form.withInitialValue (user.birthDay |> Form.Value.date)
                |> Form.withMin (Date.fromCalendarDate 1900 Time.Jan 1 |> Form.Value.date)
                |> Form.withMax (Date.fromCalendarDate 2022 Time.Jan 1 |> Form.Value.date)
                |> Form.withServerValidation
                    (\birthDate ->
                        let
                            _ =
                                birthDate |> Date.toIsoString
                        in
                        if birthDate == Date.fromCalendarDate 1969 Time.Jul 20 then
                            let
                                _ =
                                    Debug.log "Validation error!!!" birthDate
                            in
                            DataSource.succeed [ "No way, that's when the moon landing happened!" ]

                        else
                            DataSource.succeed []
                    )
            )
        |> Form.with
            (Form.date
                "checkin"
                { invalid = \_ -> "Invalid date"
                }
                (textInput "Check-in")
                |> Form.required "Required"
                |> Form.withInitialValue (user.checkIn |> Form.Value.date)
                |> Form.withMin (Date.fromCalendarDate 1900 Time.Jan 1 |> Form.Value.date)
                |> Form.withMax (Date.fromCalendarDate 2022 Time.Jan 1 |> Form.Value.date)
            )
        |> Form.with
            (Form.date
                "checkout"
                { invalid = \_ -> "Invalid date"
                }
                (textInput "Check-out")
                |> Form.required "Required"
                |> Form.withInitialValue (user.checkOut |> Form.Value.date)
                |> Form.withMin (Date.fromCalendarDate 1900 Time.Jan 1 |> Form.Value.date)
                |> Form.withMax (Date.fromCalendarDate 2022 Time.Jan 1 |> Form.Value.date)
            )
        |> Form.with
            (Form.range
                "rating"
                { missing = "Required"
                , invalid = \_ -> "Invalid number"
                }
                { initial = 3
                , min = 1
                , max = 5
                }
                (textInput "Rating")
            )
        |> Form.wrap wrapSection
        |> Form.appendForm (|>)
            (Form.succeed Tuple.pair
                |> Form.with
                    (Form.text "password"
                        (textInput "Password")
                        |> Form.password
                        |> Form.required "Required"
                    )
                |> Form.with
                    (Form.text
                        "password-confirmation"
                        (textInput "Password Confirmation")
                        |> Form.password
                        |> Form.required "Required"
                    )
                |> Form.validate
                    (\( password, passwordConfirmation ) ->
                        if password == passwordConfirmation then
                            []

                        else
                            [ ( "password-confirmation"
                              , [ "Must match password" ]
                              )
                            ]
                    )
            )
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
                                "Invalid option"
                                ( ( "PushAll", PushAll )
                                , [ ( "PushEmail", PushEmail )
                                  , ( "PushNone", PushNone )
                                  ]
                                )
                                radioInput
                                wrapPushNotificationsSection
                                |> Form.required "Please select your notification preference."
                            )
                    )
             )
                |> Form.wrap wrapNotificationsSections
            )
        |> Form.appendForm (\() rest -> rest)
            (Form.succeed identity
                |> Form.with
                    (Form.checkbox
                        "acceptTerms"
                        False
                        (checkboxInput { name = "Accept terms", description = "Please read the terms before proceeding." })
                        |> Form.withRecoverableClientValidation
                            (\checked ->
                                if checked then
                                    Ok ( (), [] )

                                else
                                    Ok ( (), [ "Please agree to terms to proceed." ] )
                            )
                    )
            )
        |> Form.append
            (Form.submit
                (\{ attrs, formHasErrors } ->
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
                            , saveButton formHasErrors attrs
                            ]
                        ]
                )
            )
        |> Form.validate
            (\user_ ->
                [ ( "checkin"
                  , if Date.compare user_.checkIn user_.checkOut == GT then
                        [ "Must be before checkout."
                        ]

                    else
                        []
                  )
                ]
            )


type PushNotificationsSetting
    = PushAll
    | PushEmail
    | PushNone


saveButton formHasErrors formAttrs =
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
                    , --if formHasErrors then
                      --    Css.batch
                      --        [ Tw.text_gray_200
                      --        , Tw.bg_indigo_500
                      --        , Tw.cursor_default
                      --        ]
                      --
                      --  else
                      Css.hover
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


route : StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = action
        }
        |> RouteBuilder.buildWithLocalState
            { view = view
            , update = update
            , init = init
            , subscriptions = \_ _ _ _ _ -> Sub.none
            }
        |> RouteBuilder.withOnAction OnAction


action : RouteParams -> Parser (DataSource (Response ActionData ErrorPage))
action routeParams =
    Form.submitHandlers
        (form defaultUser)
        (\model decoded ->
            DataSource.succeed
                { user = Result.toMaybe decoded
                , initialForm = model
                }
                |> DataSource.map Response.render
        )


update _ _ static msg model =
    case msg of
        FormMsg formMsg ->
            model.form
                |> Form.update Effect.Submit Effect.None FormMsg (form defaultUser) formMsg
                |> Tuple.mapFirst (\newFormModel -> { model | form = newFormModel })

        MovedToTop ->
            ( model, Effect.none )

        OnAction actionData ->
            loadActionData (Just actionData)


withFlash : Result String String -> ( Model, effect ) -> ( Model, effect )
withFlash flashMessage ( model, cmd ) =
    ( { model | flashMessage = Just flashMessage }, cmd )


init _ _ static =
    let
        _ =
            Debug.log "@@@static.action" static.action
    in
    loadActionData static.action


loadActionData maybeActionData =
    ( { form = maybeActionData |> Maybe.map .initialForm |> Maybe.withDefault (Form.init (form defaultUser))
      , flashMessage =
            maybeActionData
                |> Maybe.map
                    (\actionData ->
                        if Form.hasErrors actionData.initialForm then
                            Err "Got errors"

                        else
                            case actionData.user of
                                Just user ->
                                    Ok ("Successfully updated profile for user " ++ user.first ++ " " ++ user.last)

                                Nothing ->
                                    Err "Unexpected"
                    )
      }
    , Effect.none
    )


type alias Data =
    {}


type alias ActionData =
    { user : Maybe User
    , initialForm : Form.Model
    }


data : RouteParams -> Parser (DataSource (Response Data ErrorPage))
data routeParams =
    Request.oneOf
        [ {}
            |> Response.render
            |> DataSource.succeed
            |> Request.succeed
        ]


head :
    StaticPayload Data ActionData RouteParams
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



--formModelView formModel =
--    formModel
--        |> Debug.toString
--        |> Html.text
--        |> List.singleton
--        |> Html.pre
--            [ Attr.style "white-space" "break-spaces"
--            ]


view :
    Maybe PageUrl
    -> Shared.Model
    -> Model
    -> StaticPayload Data ActionData RouteParams
    -> View Msg
view maybeUrl sharedModel model static =
    let
        user : User
        user =
            static.action
                |> Maybe.andThen .user
                |> Maybe.withDefault defaultUser
    in
    { title = "Form Example"
    , body =
        [ Html.div
            []
            [ Css.Global.global Tw.globalStyles
            , model.flashMessage
                |> Maybe.map flashView
                |> Maybe.withDefault (Html.p [] [])
            , Html.p []
                [ if Form.isSubmitting model.form then
                    Html.text "Submitting..."

                  else
                    Html.text ""
                ]
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
                    |> Form.toStatefulHtml FormMsg
                        (\attrs children -> Html.form (List.map Attr.fromUnstyled attrs) children)
                        model.form
                ]
            ]
            |> Html.toUnstyled
        ]
    }


successColor : Color
successColor =
    Css.rgb 163 251 163


errorColor : Color
errorColor =
    Css.rgb 251 163 163


flashView : Result String String -> Html msg
flashView message =
    Html.p
        [ css
            [ Css.backgroundColor
                (case message of
                    Ok _ ->
                        successColor

                    Err _ ->
                        errorColor
                )
            , Tw.p_4
            ]
        ]
        [ Html.text <|
            case message of
                Ok okMessage ->
                    okMessage

                Err error ->
                    "Something went wrong: " ++ error
        ]


textInput labelText ({ toInput, toLabel, errors, submitStatus } as info) =
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
        [ --Html.text (Debug.toString submitStatus),
          Html.span
            [ css
                [ Tw.font_bold
                ]
            ]
            [ Html.text (Form.fieldStatusToString info.status) ]
        , Html.label
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
        , errorsView info
        ]


errorsView : { a | errors : List String, submitStatus : Form.SubmitStatus, status : Form.FieldStatus } -> Html msg
errorsView { errors, submitStatus, status } =
    let
        showErrors : Bool
        showErrors =
            --(status |> Form.isAtLeast Form.Focused) || submitStatus == Form.Submitting || submitStatus == Form.Submitted
            True
    in
    Html.ul
        [ css
            [ Tw.mt_2
            , Tw.text_sm
            , Tw.text_red_600
            ]
        ]
        (if showErrors then
            errors
                |> List.map
                    (\error ->
                        Html.li
                            [ css [ Tw.list_disc ]
                            ]
                            [ Html.text error ]
                    )

         else
            []
        )


checkboxInput { name, description } ({ toLabel, toInput, errors } as info) =
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
        , errorsView info
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


radioInput item { toLabel, toInput, errors, status } =
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


wrapPushNotificationsSection ({ errors, submitStatus } as info) children =
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
            [ Html.span
                [ css
                    [ Tw.font_bold
                    ]
                ]
                [ Html.text (Form.fieldStatusToString info.status) ]
            , Html.div
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
        , errorsView info
        ]
