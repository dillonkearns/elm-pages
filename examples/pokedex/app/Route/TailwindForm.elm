module Route.TailwindForm exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import Css exposing (Color)
import Css.Global
import Date exposing (Date)
import Dict exposing (Dict)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import Exception exposing (Throwable)
import Form
import Form.Field as Field
import Form.FieldStatus as FieldStatus
import Form.FieldView
import Form.Validation as Validation exposing (Combined, Field)
import Form.Value
import Head
import Head.Seo as Seo
import Html.Styled as Html exposing (Html)
import Html.Styled.Attributes as Attr exposing (css)
import Icon
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
import Server.Request as Request exposing (Parser)
import Server.Response as Response exposing (Response)
import Shared
import Tailwind.Breakpoints as Bp
import Tailwind.Utilities as Tw
import Time
import View exposing (View)


type alias Model =
    {}


type Msg
    = MovedToTop


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


usernameInput formState field =
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
                [ Attr.for "username"
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
                    , Form.FieldView.inputStyled
                        [ Attr.type_ "text"
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
                        field
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
                        [ if formState.errors |> Form.errorsForField field |> List.isEmpty then
                            Html.text ""

                          else
                            Icon.error
                        ]
                    ]
                ]
            ]
        , errorsView formState field
        ]


validateCapitalized : String -> ( Maybe String, List String )
validateCapitalized string =
    if string |> String.toList |> List.head |> Maybe.withDefault 'a' |> Char.isUpper then
        ( Just string, [] )

    else
        ( Nothing, [ "Needs to be capitalized" ] )


form : Form.DoneForm String (BackendTask Throwable (Combined String User)) data (List (Html (Pages.Msg.Msg Msg)))
form =
    Form.init
        (\first last username email dob checkin checkout rating password passwordConfirmation comments candidates offers pushNotifications acceptTerms ->
            { combine =
                Validation.succeed User
                    |> Validation.andMap first
                    |> Validation.andMap last
                    |> Validation.andMap username
                    |> Validation.andMap email
                    |> Validation.andMap dob
                    |> Validation.andMap checkin
                    |> Validation.andMap checkout
                    |> Validation.andMap rating
                    |> Validation.andMap
                        (Validation.map2
                            (\passwordValue passwordConfirmationValue ->
                                if passwordValue == passwordConfirmationValue then
                                    Validation.succeed ( passwordValue, passwordConfirmationValue )

                                else
                                    passwordConfirmation
                                        |> Validation.fail "Must match password"
                            )
                            password
                            passwordConfirmation
                            |> Validation.andThen identity
                        )
                    |> Validation.andMap
                        (Validation.succeed NotificationPreferences
                            |> Validation.andMap comments
                            |> Validation.andMap candidates
                            |> Validation.andMap offers
                            |> Validation.andMap pushNotifications
                        )
                    |> Validation.andThen
                        (\validated ->
                            if Date.toRataDie validated.checkIn >= Date.toRataDie validated.checkOut then
                                Validation.succeed validated |> Validation.withError checkin "Must be before checkout"

                            else
                                Validation.succeed validated
                        )
                    |> Validation.andThen
                        (\clientValidatedForm ->
                            Validation.map2
                                (\dobValue usernameValue ->
                                    isValidDob dobValue
                                        |> BackendTask.map
                                            (\maybeError ->
                                                case maybeError of
                                                    Nothing ->
                                                        Validation.succeed clientValidatedForm

                                                    Just error ->
                                                        dob |> Validation.fail error
                                            )
                                        |> BackendTask.map
                                            (Validation.withErrorIf (usernameValue == "asdf") username "username is taken")
                                )
                                dob
                                username
                        )
            , view =
                \formState ->
                    let
                        fieldView labelText field =
                            textInput formState labelText field
                    in
                    [ wrapSection
                        [ fieldView "First name" first
                        , fieldView "Last name" last
                        , usernameInput formState username
                        , fieldView "Email" email
                        , fieldView "Date of Birth" dob
                        , fieldView "Check-in" checkin
                        , fieldView "Check-out" checkout
                        , fieldView "Rating" rating
                        ]
                    , fieldView "Password" password
                    , fieldView "Password Confirmation" passwordConfirmation
                    , wrapEmailSection
                        [ checkboxInput { name = "Comments", description = "Get notified when someones posts a comment on a posting." } formState comments
                        , checkboxInput { name = "Candidates", description = "Get notified when a candidate applies for a job." } formState candidates
                        , checkboxInput { name = "Offers", description = "Get notified when a candidate accepts or rejects an offer." } formState offers
                        ]
                    , wrapNotificationsSections
                        [ wrapPushNotificationsSection formState
                            pushNotifications
                            [ Form.FieldView.radioStyled
                                [ css
                                    [ Tw.mt_4
                                    , Tw.space_y_4
                                    ]
                                ]
                                (radioInput [])
                                pushNotifications
                            ]
                        ]
                    , checkboxInput { name = "Accept terms", description = "Please read the terms before proceeding." } formState acceptTerms
                    , Html.div
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
                            , saveButton False []
                            ]
                        ]
                    ]
            }
        )
        |> Form.field "first"
            (Field.text
                |> Field.required "Required"
                |> Field.withInitialValue (always defaultUser.first >> Form.Value.string)
                |> Field.withClientValidation validateCapitalized
            )
        |> Form.field "last"
            (Field.text
                |> Field.required "Required"
                |> Field.withInitialValue (always defaultUser.last >> Form.Value.string)
                |> Field.withClientValidation validateCapitalized
            )
        |> Form.field "username"
            (Field.text
                |> Field.withInitialValue (always defaultUser.username >> Form.Value.string)
                |> Field.required "Required"
                |> Field.withClientValidation
                    (\username ->
                        ( Just username
                        , if username |> String.contains "@" then
                            [ "Cannot contain @ symbol" ]

                          else
                            []
                        )
                    )
                |> Field.withClientValidation
                    (\username ->
                        ( Just username
                        , if username |> String.contains "#" then
                            [ "Cannot contain # symbol" ]

                          else
                            []
                        )
                    )
                |> Field.withClientValidation
                    (\username ->
                        ( Just username
                        , if (username |> String.length) < 3 then
                            [ "Must be at least 3 characters long" ]

                          else
                            []
                        )
                    )
            )
        |> Form.field "email"
            (Field.text
                |> Field.withInitialValue (always defaultUser.email >> Form.Value.string)
                |> Field.email
                |> Field.required "Required"
            )
        |> Form.field "dob"
            (Field.date
                { invalid = \_ -> "Invalid date" }
                |> Field.required "Required"
                |> Field.withMin (Date.fromCalendarDate 1900 Time.Jan 1 |> Form.Value.date) "Choose a later date"
                |> Field.withMax (Date.fromCalendarDate 2022 Time.Jan 1 |> Form.Value.date) "Choose an earlier date"
                |> Field.withInitialValue (always defaultUser.birthDay >> Form.Value.date)
            )
        |> Form.field "checkin"
            (Field.date
                { invalid = \_ -> "Invalid date" }
                |> Field.required "Required"
                |> Field.withInitialValue (always defaultUser.checkIn >> Form.Value.date)
            )
        |> Form.field "checkout"
            (Field.date
                { invalid = \_ -> "Invalid date" }
                |> Field.required "Required"
                |> Field.withInitialValue (always defaultUser.checkOut >> Form.Value.date)
            )
        |> Form.field "rating"
            (Field.int { invalid = \_ -> "Invalid number" }
                |> Field.range
                    { missing = "Required"
                    , invalid = \_ -> "Outside range"
                    , initial = \_ -> Form.Value.int 3
                    , min = Form.Value.int 1
                    , max = Form.Value.int 5
                    }
            )
        |> Form.field "password"
            (Field.text |> Field.password |> Field.required "Required")
        |> Form.field "password-confirmation"
            (Field.text |> Field.password |> Field.required "Required")
        |> Form.field "comments"
            Field.checkbox
        |> Form.field "candidates"
            Field.checkbox
        |> Form.field "offers"
            Field.checkbox
        |> Form.field
            "push-notifications"
            (Field.select
                [ ( "PushAll", PushAll )
                , ( "PushEmail", PushEmail )
                , ( "PushNone", PushNone )
                ]
                (\_ -> "Invalid option")
                |> Field.required "Please select your notification preference."
            )
        |> Form.field "acceptTerms"
            (Field.checkbox
                |> Field.withClientValidation
                    (\checked ->
                        ( Just ()
                        , if checked then
                            []

                          else
                            [ "Please agree to terms to proceed." ]
                        )
                    )
            )


isValidDob : Date -> BackendTask Throwable (Maybe String)
isValidDob birthDate =
    if birthDate == Date.fromCalendarDate 1969 Time.Jul 20 then
        BackendTask.succeed (Just "No way, that's when the moon landing happened!")

    else
        BackendTask.succeed Nothing


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


action : RouteParams -> Parser (BackendTask Throwable (Response ActionData ErrorPage))
action routeParams =
    Request.formDataWithServerValidation (form |> Form.initCombined identity)
        |> Request.map
            (\toBackendTask ->
                toBackendTask
                    |> BackendTask.andThen
                        (\result ->
                            case result of
                                Ok ( _, user ) ->
                                    BackendTask.succeed
                                        { user = user
                                        , flashMessage =
                                            Ok ("Successfully updated profile for user " ++ user.first ++ " " ++ user.last)
                                        , formResponse = Nothing
                                        }
                                        |> BackendTask.map Response.render

                                Err (Form.Response error) ->
                                    BackendTask.succeed
                                        { flashMessage = Err "Got errors"
                                        , user = defaultUser
                                        , formResponse = Just error
                                        }
                                        |> BackendTask.map Response.render
                        )
            )


update : a -> b -> c -> Msg -> Model -> ( Model, Effect Msg )
update _ _ _ msg model =
    case msg of
        MovedToTop ->
            ( model, Effect.none )


init _ _ static =
    ( {}, Effect.none )


type alias Data =
    {}


type alias ActionData =
    { user : User
    , flashMessage : Result String String
    , formResponse : Maybe { fields : List ( String, String ), errors : Dict String (List String) }
    }


data : RouteParams -> Parser (BackendTask Throwable (Response Data ErrorPage))
data routeParams =
    Request.oneOf
        [ {}
            |> Response.render
            |> BackendTask.succeed
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
    -> View (Pages.Msg.Msg Msg)
view maybeUrl sharedModel model static =
    let
        user : User
        user =
            static.action
                |> Maybe.map .user
                |> Maybe.withDefault defaultUser
    in
    { title = "Form Example"
    , body =
        [ Html.div []
            [ Css.Global.global Tw.globalStyles
            , static.action
                |> Maybe.map .flashMessage
                |> Maybe.map flashView
                |> Maybe.withDefault (Html.p [] [])
            , Html.p []
                [ -- TODO should this be calling a function in Form and passing in the form, like `Form.isSubmitting form`?
                  if static.transition /= Nothing then
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
                [ Html.text
                    (static.action
                        |> Maybe.andThen .formResponse
                        |> Debug.toString
                    )
                , form
                    |> Form.toDynamicTransition "test"
                    |> Form.renderStyledHtml []
                        (static.action
                            |> Maybe.andThen .formResponse
                        )
                        static
                        ()
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


textInput info labelText field =
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
            [ Html.text
                (field
                    |> Validation.fieldStatus
                    |> FieldStatus.fieldStatusToString
                )
            ]
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
             -- TODO need for="..." attribute on label
             --++ styleAttrs toLabel
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
            [ field
                |> Form.FieldView.inputStyled
                    [ --Attr.attribute "autocomplete" "given-name",
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
            ]
        , errorsView info field
        ]


errorsView : Form.Context String data -> Field String parsed kind -> Html msg
errorsView formState field =
    let
        showErrors : Bool
        showErrors =
            --formState.submitAttempted
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
            formState.errors
                |> Form.errorsForField field
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


checkboxInput { name, description } info field =
    Html.div
        [ css
            [ Tw.max_w_lg
            , Tw.space_y_4
            ]
        ]
        [ Html.label
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
                [ field
                    |> Form.FieldView.inputStyled
                        [ css
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
                ]
            , Html.div
                [ css
                    [ Tw.ml_3
                    , Tw.text_sm
                    ]
                ]
                [ Html.div
                    [ css
                        [ Tw.font_medium
                        , Tw.text_gray_700
                        ]
                    ]
                    [ Html.text name ]
                , Html.p
                    [ css
                        [ Tw.text_gray_500
                        ]
                    ]
                    [ Html.text description ]
                ]
            ]
        , errorsView info field
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


radioInput errors item toRadio =
    Html.label
        [ css
            [ Tw.ml_3
            , Tw.block
            , Tw.text_sm
            , Tw.font_medium
            , Tw.text_gray_700
            ]
        ]
        [ Html.div
            [ css
                [ Tw.flex
                , Tw.items_center
                ]
            ]
            [ toRadio
                [ css
                    [ Tw.h_4
                    , Tw.w_4
                    , Tw.text_indigo_600
                    , Tw.border_gray_300
                    , Tw.mr_2
                    , Css.focus
                        [ Tw.ring_indigo_500
                        ]
                    ]
                ]
            , (case item of
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


wrapPushNotificationsSection formState field children =
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
                [ Html.text
                    (field
                        |> Validation.fieldStatus
                        |> FieldStatus.fieldStatusToString
                    )
                ]
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
        , errorsView formState field
        ]
