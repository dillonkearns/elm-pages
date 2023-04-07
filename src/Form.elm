module Form exposing
    ( Form, HtmlForm, StyledHtmlForm, DoneForm
    , form
    , field
    , Context
    , Errors, errorsForField
    , renderHtml, renderStyledHtml
    , Options, options
    , withInput, withOnSubmit, withServerResponse
    , parse
    , hiddenField, hiddenKind
    , withGetMethod
    , dynamic
    , Msg, Model, init, update
    , Validated(..)
    , ServerResponse
    , mapMsg, toResult
    , Method(..), methodToString
    -- subGroup
    )

{-|


## Example

Let's look at a sign-up form example.


### Step 1 - Define the Form

What to look for:

**The field declarations**

Below the `Form.form` call you will find all of the form's fields declared with

    |> Form.field ...

These are the form's field declarations.

These fields each have individual validations. For example, `|> Field.required ...` means we'll get a validation
error if that field is empty (similar for checking the minimum password length).

There will be a corresponding parameter in the function we pass in to `Form.form` for every
field declaration (in this example, `\email password passwordConfirmation -> ...`).

**The `combine` validation**

In addition to the validation errors that individual fields can have independently (like
required fields or minimum password length), we can also do _dependent validations_.

We use the [`Form.Validation`](Form-Validation) module to take each individual field and combine
them into a type and/or errors.

**The `view`**

Totally customizable. Uses [`Form.FieldView`](Form-FieldView) to render all of the fields declared.

    import BackendTask exposing (BackendTask)
    import ErrorPage exposing (ErrorPage)
    import Form
    import Form.Field as Field
    import Form.FieldView as FieldView
    import Form.Validation as Validation
    import Html exposing (Html)
    import Html.Attributes as Attr
    import Route
    import Server.Request as Request
    import Server.Response exposing (Response)

    type alias NewUser =
        { email : String
        , password : String
        }

    signupForm : Form.HtmlForm String NewUser () Msg
    signupForm =
        Form.form
            (\email password passwordConfirmation ->
                { combine =
                    Validation.succeed Login
                        |> Validation.andMap email
                        |> Validation.andMap
                            (Validation.map2
                                (\pass confirmation ->
                                    if pass == confirmation then
                                        Validation.succeed pass

                                    else
                                        passwordConfirmation
                                            |> Validation.fail
                                                "Must match password"
                                )
                                password
                                passwordConfirmation
                                |> Validation.andThen identity
                            )
                , view =
                    \info ->
                        [ Html.label []
                            [ fieldView info "Email" email
                            , fieldView info "Password" password
                            , fieldView info "Confirm Password" passwordConfirmation
                            ]
                        , Html.button []
                            [ if info.submitting then
                                Html.text "Signing Up..."

                              else
                                Html.text "Sign Up"
                            ]
                        ]
                }
            )
            |> Form.field "email"
                (Field.text
                    |> Field.required "Required"
                )
            |> Form.field "password"
                passwordField
            |> Form.field "passwordConfirmation"
                passwordField

    passwordField =
        Field.text
            |> Field.password
            |> Field.required "Required"
            |> Field.withClientValidation
                (\password ->
                    ( Just password
                    , if String.length password < 4 then
                        [ "Must be at least 4 characters" ]

                      else
                        []
                    )
                )

    fieldView :
        Form.Context String input
        -> String
        -> Validation.Field String parsed FieldView.Input
        -> Html msg
    fieldView formState label field =
        Html.div []
            [ Html.label []
                [ Html.text (label ++ " ")
                , field |> Form.FieldView.input []
                ]
            , (if formState.submitAttempted then
                formState.errors
                    |> Form.errorsForField field
                    |> List.map
                        (\error ->
                            Html.li [] [ Html.text error ]
                        )

               else
                []
              )
                |> Html.ul [ Attr.style "color" "red" ]
            ]


### Step 2 - Render the Form's View

    view maybeUrl sharedModel app =
        { title = "Sign Up"
        , body =
            [ form
                |> Form.renderHtml "login" [] Nothing app ()
            ]
        }


### Step 3 - Handle Server-Side Form Submissions

    action : RouteParams -> Request.Parser (BackendTask (Response ActionData ErrorPage))
    action routeParams =
        Request.formData [ signupForm ]
            |> Request.map
                (\signupResult ->
                    case signupResult of
                        Ok newUser ->
                            newUser
                                |> myCreateUserBackendTask
                                |> BackendTask.map
                                    (\() ->
                                        -- redirect to the home page
                                        -- after successful sign-up
                                        Route.redirectTo Route.Index
                                    )

                        Err _ ->
                            Route.redirectTo Route.Login
                                |> BackendTask.succeed
                )

    myCreateUserBackendTask : BackendTask ()
    myCreateUserBackendTask =
        BackendTask.fail
            "TODO - make a database call to create a new user"


## Building a Form Parser

@docs Form, HtmlForm, StyledHtmlForm, DoneForm

@docs form


### Adding Fields

@docs field


## View Functions

@docs Context


## Showing Errors

@docs Errors, errorsForField


## Rendering Forms

@docs renderHtml, renderStyledHtml

@docs Options, options

@docs withInput, withOnSubmit, withServerResponse


## Running Parsers

@docs parse


## Progressively Enhanced Form Techniques (elm-pages)


### Hidden Fields

Hidden fields are a useful technique when you are progressively enhancing form submissions and sending the key-value form data directly.
In `elm-pages` apps this is used often and is an idiomatic approach. If you are wiring up your own `onSubmit` with a Msg
and never submit the forms directly, then you will likely include additional context as part of your `Msg` instead of
through hidden fields.

@docs hiddenField, hiddenKind


### GET Forms

@docs withGetMethod


## Dynamic Fields

@docs dynamic


## Wiring

`elm-form` manages the client-side state of fields, including FieldStatus which you can use to determine when
in the user's workflow to show validation errors.

@docs Msg, Model, init, update

@docs Validated

@docs ServerResponse

@docs mapMsg, toResult

@docs Method, methodToString

-}

import Dict exposing (Dict)
import Form.Field as Field exposing (Field)
import Form.FieldStatus exposing (FieldStatus)
import Form.FieldView
import Form.Validation exposing (Combined)
import Html exposing (Html)
import Html.Attributes as Attr
import Html.Lazy
import Html.Styled
import Html.Styled.Attributes as StyledAttr
import Html.Styled.Lazy
import Internal.Field
import Internal.FieldEvent exposing (Event(..), FieldEvent)
import Internal.Form
import Internal.Input
import Pages.FormState as Form exposing (FormState)
import Pages.Internal.Form exposing (Validation(..))
import Task


{-| -}
type Validated error value
    = Valid value
    | Invalid (Maybe value) (Dict String (List error))


{-| -}
toResult : Validated error value -> Result ( Maybe value, Dict String (List error) ) value
toResult validated =
    case validated of
        Valid value ->
            Ok value

        Invalid maybeParsed errors ->
            Err ( maybeParsed, errors )


{-| -}
initFormState : FormState
initFormState =
    { fields = Dict.empty
    , submitAttempted = False
    }


{-| -}
type alias Context error input =
    { errors : Errors error
    , submitting : Bool
    , submitAttempted : Bool
    , input : input
    }


{-| -}
form : combineAndView -> Form String combineAndView parsed input
form combineAndView =
    Internal.Form.Form
        []
        (\_ _ ->
            { result = Dict.empty
            , combineAndView = combineAndView
            , isMatchCandidate = True
            }
        )
        (\_ -> [])


{-| -}
dynamic :
    (decider
     ->
        Form
            error
            { combine : Form.Validation.Validation error parsed named constraints1
            , view : subView
            }
            parsed
            input
    )
    ->
        Form
            error
            --((decider -> Validation error parsed named) -> combined)
            ({ combine : decider -> Form.Validation.Validation error parsed named constraints1
             , view : decider -> subView
             }
             -> combineAndView
            )
            parsed
            input
    ->
        Form
            error
            combineAndView
            parsed
            input
dynamic forms formBuilder =
    Internal.Form.Form
        []
        (\maybeData formState ->
            let
                toParser :
                    decider
                    ->
                        { result : Dict String (List error)
                        , isMatchCandidate : Bool
                        , combineAndView : { combine : Validation error parsed named constraints1, view : subView }
                        }
                toParser decider =
                    case forms decider of
                        Internal.Form.Form _ parseFn _ ->
                            -- TODO need to include hidden form fields from `definitions` (should they be automatically rendered? Does that mean the view type needs to be hardcoded?)
                            parseFn maybeData formState

                myFn :
                    { result : Dict String (List error)
                    , isMatchCandidate : Bool
                    , combineAndView : combineAndView
                    }
                myFn =
                    let
                        newThing :
                            { result : Dict String (List error)
                            , isMatchCandidate : Bool
                            , combineAndView : { combine : decider -> Validation error parsed named constraints1, view : decider -> subView } -> combineAndView
                            }
                        newThing =
                            case formBuilder of
                                Internal.Form.Form _ parseFn _ ->
                                    parseFn maybeData formState

                        arg : { combine : decider -> Validation error parsed named constraints1, view : decider -> subView }
                        arg =
                            { combine =
                                toParser
                                    >> .combineAndView
                                    >> .combine
                            , view =
                                \decider ->
                                    decider
                                        |> toParser
                                        |> .combineAndView
                                        |> .view
                            }
                    in
                    { result =
                        newThing.result
                    , combineAndView =
                        newThing.combineAndView arg
                    , isMatchCandidate = newThing.isMatchCandidate
                    }
            in
            myFn
        )
        (\_ -> [])



--{-| -}
--subGroup :
--    Form error ( Maybe parsed, Dict String (List error) ) input (Context error input -> subView)
--    ->
--        Form
--            error
--            ({ value : parsed } -> combined)
--            input
--            (Context error input -> (subView -> combinedView))
--    -> Form error combined input (Context error input -> combinedView)
--subGroup forms formBuilder =
--    Form []
--        (\maybeData formState ->
--            let
--                toParser : { result : ( Maybe ( Maybe parsed, Dict String (List error) ), Dict String (List error) ), view : Context error input -> subView }
--                toParser =
--                    case forms of
--                        Form definitions parseFn toInitialValues ->
--                            -- TODO need to include hidden form fields from `definitions` (should they be automatically rendered? Does that mean the view type needs to be hardcoded?)
--                            parseFn maybeData formState
--
--                myFn :
--                    { result : ( Maybe combined, Dict String (List error) )
--                    , view : Context error input -> combinedView
--                    }
--                myFn =
--                    let
--                        deciderToParsed : ( Maybe parsed, Dict String (List error) )
--                        deciderToParsed =
--                            toParser |> mergeResults
--
--                        newThing : { result : ( Maybe ({ value : parsed } -> combined), Dict String (List error) ), view : Context error input -> subView -> combinedView }
--                        newThing =
--                            case formBuilder of
--                                Form definitions parseFn toInitialValues ->
--                                    parseFn maybeData formState
--
--                        anotherThing : Maybe combined
--                        anotherThing =
--                            Maybe.map2
--                                (\runFn parsed ->
--                                    runFn { value = parsed }
--                                )
--                                (Tuple.first newThing.result)
--                                (deciderToParsed |> Tuple.first)
--                    in
--                    { result =
--                        ( anotherThing
--                        , mergeErrors (newThing.result |> Tuple.second)
--                            (deciderToParsed |> Tuple.second)
--                        )
--                    , view =
--                        \fieldErrors ->
--                            let
--                                something2 : subView
--                                something2 =
--                                    fieldErrors
--                                        |> (toParser
--                                                |> .view
--                                           )
--                            in
--                            newThing.view fieldErrors something2
--                    }
--            in
--            myFn
--        )
--        (\_ -> [])


{-| Declare a visible field for the form.

Use [`Form.Field`](Form-Field) to define the field and its validations.

    form =
        Form.form
            (\email ->
                { combine =
                    Validation.succeed NewUser
                        |> Validation.andMap email
                , view = \info -> [{- render fields -}]
                }
            )
            |> Form.field "email"
                (Field.text |> Field.required "Required")

-}
field :
    String
    -> Field error parsed input initial kind constraints
    -> Form error (Form.Validation.Field error parsed kind -> combineAndView) parsedCombined input
    -> Form error combineAndView parsedCombined input
field name (Internal.Field.Field fieldParser kind) (Internal.Form.Form definitions parseFn toInitialValues) =
    Internal.Form.Form
        (( name, Internal.Form.RegularField )
            :: definitions
        )
        (\maybeData formState ->
            let
                ( maybeParsed, errors ) =
                    -- @@@@@@ use code from here
                    fieldParser.decode rawFieldValue

                ( rawFieldValue, fieldStatus ) =
                    case formState.fields |> Dict.get name of
                        Just info ->
                            ( Just info.value, info.status )

                        Nothing ->
                            ( maybeData |> Maybe.andThen (\data -> fieldParser.initialValue data), Form.FieldStatus.notVisited )

                thing : Pages.Internal.Form.ViewField kind
                thing =
                    { value = rawFieldValue
                    , status = fieldStatus
                    , kind = ( kind, fieldParser.properties )
                    }

                parsedField : Form.Validation.Field error parsed kind
                parsedField =
                    Pages.Internal.Form.Validation (Just thing) (Just name) ( maybeParsed, Dict.empty )

                myFn :
                    { result : Dict String (List error)
                    , combineAndView : Form.Validation.Field error parsed kind -> combineAndView
                    , isMatchCandidate : Bool
                    }
                    ->
                        { result : Dict String (List error)
                        , combineAndView : combineAndView
                        , isMatchCandidate : Bool
                        }
                myFn soFar =
                    let
                        validationField : Form.Validation.Field error parsed kind
                        validationField =
                            parsedField
                    in
                    { result =
                        soFar.result
                            |> addErrorsInternal name errors
                    , combineAndView =
                        soFar.combineAndView validationField
                    , isMatchCandidate = soFar.isMatchCandidate
                    }
            in
            formState
                |> parseFn maybeData
                |> myFn
        )
        (\input ->
            case fieldParser.initialValue input of
                Just initialValue ->
                    ( name, Just initialValue )
                        :: toInitialValues input

                Nothing ->
                    toInitialValues input
        )


{-| Declare a hidden field for the form.

Unlike [`field`](#field) declarations which are rendered using [`Form.FieldView`](Form-FieldView)
functions, `hiddenField` inputs are automatically inserted into the form when you render it.

You define the field's validations the same way as for `field`, with the
[`Form.Field`](Form-Field) API.

    form =
        Form.form
            (\quantity productId ->
                { combine = {- combine fields -}
                , view = \info -> [{- render visible fields -}]
                }
            )
            |> Form.field "quantity"
                (Field.int |> Field.required "Required")
            |> Form.field "productId"
                (Field.text
                    |> Field.required "Required"
                    |> Field.withInitialValue (\product -> Form.Value.string product.id)
                )

-}
hiddenField :
    String
    -> Field error parsed input initial kind constraints
    -> Form error (Form.Validation.Field error parsed Form.FieldView.Hidden -> combineAndView) parsedCombined input
    -> Form error combineAndView parsedCombined input
hiddenField name (Internal.Field.Field fieldParser _) (Internal.Form.Form definitions parseFn toInitialValues) =
    Internal.Form.Form
        (( name, Internal.Form.HiddenField )
            :: definitions
        )
        (\maybeData formState ->
            let
                ( maybeParsed, errors ) =
                    fieldParser.decode rawFieldValue

                ( rawFieldValue, fieldStatus ) =
                    case formState.fields |> Dict.get name of
                        Just info ->
                            ( Just info.value, info.status )

                        Nothing ->
                            ( maybeData |> Maybe.andThen (\data -> fieldParser.initialValue data), Form.FieldStatus.notVisited )

                thing : Pages.Internal.Form.ViewField Form.FieldView.Hidden
                thing =
                    { value = rawFieldValue
                    , status = fieldStatus
                    , kind = ( Internal.Input.Hidden, fieldParser.properties )
                    }

                parsedField : Form.Validation.Field error parsed Form.FieldView.Hidden
                parsedField =
                    Pages.Internal.Form.Validation (Just thing) (Just name) ( maybeParsed, Dict.empty )

                myFn :
                    { result : Dict String (List error)
                    , combineAndView : Form.Validation.Field error parsed Form.FieldView.Hidden -> combineAndView
                    , isMatchCandidate : Bool
                    }
                    ->
                        { result : Dict String (List error)
                        , combineAndView : combineAndView
                        , isMatchCandidate : Bool
                        }
                myFn soFar =
                    let
                        validationField : Form.Validation.Field error parsed Form.FieldView.Hidden
                        validationField =
                            parsedField
                    in
                    { result =
                        soFar.result
                            |> addErrorsInternal name errors
                    , combineAndView =
                        soFar.combineAndView validationField
                    , isMatchCandidate = soFar.isMatchCandidate
                    }
            in
            formState
                |> parseFn maybeData
                |> myFn
        )
        (\input ->
            case fieldParser.initialValue input of
                Just initialValue ->
                    ( name, Just initialValue )
                        :: toInitialValues input

                Nothing ->
                    toInitialValues input
        )


{-| -}
hiddenKind :
    ( String, String )
    -> error
    -> Form error combineAndView parsed input
    -> Form error combineAndView parsed input
hiddenKind ( name, value ) error_ (Internal.Form.Form definitions parseFn toInitialValues) =
    let
        (Internal.Field.Field fieldParser _) =
            Field.exactValue value error_
    in
    Internal.Form.Form
        (( name, Internal.Form.HiddenField )
            :: definitions
        )
        (\maybeData formState ->
            let
                ( decodedValue, errors ) =
                    fieldParser.decode rawFieldValue

                rawFieldValue : Maybe String
                rawFieldValue =
                    case formState.fields |> Dict.get name of
                        Just info ->
                            Just info.value

                        Nothing ->
                            maybeData |> Maybe.andThen (\data -> fieldParser.initialValue data)

                myFn :
                    { result : Dict String (List error)
                    , isMatchCandidate : Bool
                    , combineAndView : combineAndView
                    }
                    ->
                        { result : Dict String (List error)
                        , isMatchCandidate : Bool
                        , combineAndView : combineAndView
                        }
                myFn soFar =
                    { result =
                        soFar.result
                            |> addErrorsInternal name errors
                    , combineAndView = soFar.combineAndView
                    , isMatchCandidate = soFar.isMatchCandidate && decodedValue == Just value
                    }
            in
            formState
                |> parseFn maybeData
                |> myFn
        )
        (\input ->
            ( name, Just value )
                :: toInitialValues input
        )


{-| -}
type Errors error
    = Errors (Dict String (List error))


{-| -}
errorsForField : Form.Validation.Field error parsed kind -> Errors error -> List error
errorsForField field_ (Errors errorsDict) =
    errorsDict
        |> Dict.get (Form.Validation.fieldName field_)
        |> Maybe.withDefault []


mergeResults :
    { a | result : ( Validation error parsed named constraints1, Dict String (List error) ) }
    -> Validation error parsed unnamed constraints2
mergeResults parsed =
    case parsed.result of
        ( Pages.Internal.Form.Validation _ name ( parsedThing, combineErrors ), individualFieldErrors ) ->
            Pages.Internal.Form.Validation Nothing
                name
                ( parsedThing
                , mergeErrors combineErrors individualFieldErrors
                )


mergeErrors : Dict comparable (List value) -> Dict comparable (List value) -> Dict comparable (List value)
mergeErrors errors1 errors2 =
    Dict.merge
        (\key entries soFar ->
            soFar |> insertIfNonempty key entries
        )
        (\key entries1 entries2 soFar ->
            soFar |> insertIfNonempty key (entries1 ++ entries2)
        )
        (\key entries soFar ->
            soFar |> insertIfNonempty key entries
        )
        errors1
        errors2
        Dict.empty


{-| -}
parse :
    String
    -> Model
    -> input
    -> Form error { info | combine : Form.Validation.Validation error parsed named constraints } parsed input
    -> Validated error parsed
parse formId state input (Internal.Form.Form _ parser _) =
    -- TODO Get transition context from `app` so you can check if the current form is being submitted
    -- TODO either as a transition or a fetcher? Should be easy enough to check for the `id` on either of those?
    let
        parsed :
            { result : Dict String (List error)
            , isMatchCandidate : Bool
            , combineAndView : { info | combine : Validation error parsed named constraints }
            }
        parsed =
            parser (Just input) thisFormState

        thisFormState : FormState
        thisFormState =
            state
                |> Dict.get formId
                |> Maybe.withDefault initFormState
    in
    case
        { result = ( parsed.combineAndView.combine, parsed.result )
        }
            |> mergeResults
            |> unwrapValidation
    of
        ( Just justParsed, errors ) ->
            if Dict.isEmpty errors then
                Valid justParsed

            else
                Invalid (Just justParsed) errors

        ( Nothing, errors ) ->
            Invalid Nothing errors


insertIfNonempty : comparable -> List value -> Dict comparable (List value) -> Dict comparable (List value)
insertIfNonempty key values dict =
    if values |> List.isEmpty then
        dict

    else
        dict
            |> Dict.insert key values


unwrapValidation : Validation error parsed named constraints -> ( Maybe parsed, Dict String (List error) )
unwrapValidation (Pages.Internal.Form.Validation _ _ ( maybeParsed, errors )) =
    ( maybeParsed, errors )


{-| -}
renderHtml :
    { submitting : Bool
    , state : Model
    , toMsg : Msg mappedMsg -> mappedMsg
    }
    -> Options error parsed input mappedMsg
    -> List (Html.Attribute mappedMsg)
    ->
        Form
            error
            { combine : Form.Validation.Validation error parsed named constraints
            , view : Context error input -> List (Html mappedMsg)
            }
            parsed
            input
    -> Html mappedMsg
renderHtml state options_ attrs form_ =
    Html.Lazy.lazy4 renderHelper state options_ attrs form_


{-| -}
renderStyledHtml :
    { submitting : Bool
    , state : Model
    , toMsg : Msg mappedMsg -> mappedMsg
    }
    -> Options error parsed input mappedMsg
    -> List (Html.Styled.Attribute mappedMsg)
    ->
        Form
            error
            { combine : Form.Validation.Validation error parsed field constraints
            , view : Context error input -> List (Html.Styled.Html mappedMsg)
            }
            parsed
            input
    -> Html.Styled.Html mappedMsg
renderStyledHtml state options_ attrs form_ =
    Html.Styled.Lazy.lazy4 renderStyledHelper state options_ attrs form_


{-| The `persisted` state will be ignored if the client already has a form state. It is useful for persisting state between page loads. For example, `elm-pages` server-rendered routes
use this `persisted` state in order to show client-side validations and preserve form field state when a submission is done with JavaScript disabled in the user's browser.

`serverSideErrors` will show on the client-side error state until the form is re-submitted. For example, if you need to check that a username is unique, you can do so by including
an error in `serverSideErrors` in the response back from the server. The client-side form will show the error until the user changes the username and re-submits the form, allowing the
server to re-validate that input.

-}
type alias ServerResponse error =
    { persisted :
        { fields : Maybe (List ( String, String ))
        , clientSideErrors : Maybe (Dict String (List error))
        }
    , serverSideErrors : Dict String (List error)
    }


renderHelper :
    { submitting : Bool
    , state : Model
    , toMsg : Msg mappedMsg -> mappedMsg
    }
    -> Options error parsed input mappedMsg
    -> List (Html.Attribute mappedMsg)
    ->
        Form
            error
            { combine : Form.Validation.Validation error parsed named constraints
            , view : Context error input -> List (Html mappedMsg)
            }
            parsed
            input
    -> Html mappedMsg
renderHelper formState options_ attrs ((Internal.Form.Form _ _ _) as form_) =
    -- TODO Get transition context from `app` so you can check if the current form is being submitted
    -- TODO either as a transition or a fetcher? Should be easy enough to check for the `id` on either of those?
    let
        { hiddenInputs, children, parsed, fields, errors } =
            helperValues options_ toHiddenInput formState form_

        toHiddenInput : List (Html.Attribute mappedMsg) -> Html mappedMsg
        toHiddenInput hiddenAttrs =
            Html.input hiddenAttrs []
    in
    Html.form
        ((Form.listeners options_.id
            |> List.map (Attr.map (Internal.FieldEvent.FormFieldEvent >> formState.toMsg))
         )
            ++ [ Attr.method (methodToString options_.method)
               , Attr.novalidate True

               -- TODO get Path from options (make it configurable, `withPath`)
               --, Attr.action ("/" ++ String.join "/" formState.path)
               ]
            ++ [ Internal.FieldEvent.formDataOnSubmit
                    |> Attr.map
                        (\formDataThing ->
                            let
                                maybeFormMsg : Maybe mappedMsg
                                maybeFormMsg =
                                    options_.onSubmit
                                        |> Maybe.map
                                            (\onSubmit ->
                                                onSubmit
                                                    { fields = formDataThing.fields |> Maybe.withDefault fields
                                                    , action = formDataThing.action
                                                    , method =
                                                        case formDataThing.method of
                                                            Internal.FieldEvent.Get ->
                                                                Get

                                                            Internal.FieldEvent.Post ->
                                                                Post
                                                    , parsed =
                                                        case parsed of
                                                            Just justParsed ->
                                                                if Dict.isEmpty errors then
                                                                    Valid justParsed

                                                                else
                                                                    Invalid (Just justParsed) errors

                                                            Nothing ->
                                                                Invalid Nothing errors
                                                    }
                                            )
                            in
                            Internal.FieldEvent.Submit formDataThing maybeFormMsg
                                |> formState.toMsg
                        )
               ]
            ++ attrs
        )
        (hiddenInputs ++ children)


renderStyledHelper :
    { submitting : Bool
    , state : Model
    , toMsg : Msg mappedMsg -> mappedMsg
    }
    -> Options error parsed input mappedMsg
    -> List (Html.Styled.Attribute mappedMsg)
    ->
        Form
            error
            { combine : Form.Validation.Validation error parsed field constraints
            , view : Context error input -> List (Html.Styled.Html mappedMsg)
            }
            parsed
            input
    -> Html.Styled.Html mappedMsg
renderStyledHelper formState options_ attrs ((Internal.Form.Form _ _ _) as form_) =
    -- TODO Get transition context from `app` so you can check if the current form is being submitted
    -- TODO either as a transition or a fetcher? Should be easy enough to check for the `id` on either of those?
    let
        { hiddenInputs, children, parsed, fields, errors } =
            helperValues options_ toHiddenInput formState form_

        toHiddenInput : List (Html.Attribute msg) -> Html.Styled.Html msg
        toHiddenInput hiddenAttrs =
            Html.Styled.input (hiddenAttrs |> List.map StyledAttr.fromUnstyled) []
    in
    Html.Styled.form
        ((Form.listeners options_.id
            |> List.map (Attr.map (Internal.FieldEvent.FormFieldEvent >> formState.toMsg))
            |> List.map StyledAttr.fromUnstyled
         )
            ++ [ StyledAttr.method (methodToString options_.method)
               , StyledAttr.novalidate True

               -- TODO
               --, StyledAttr.action ("/" ++ String.join "/" formState.path)
               ]
            ++ [ Internal.FieldEvent.formDataOnSubmit
                    |> Attr.map
                        (\formDataThing ->
                            let
                                maybeFormMsg : Maybe mappedMsg
                                maybeFormMsg =
                                    options_.onSubmit
                                        |> Maybe.map
                                            (\onSubmit ->
                                                onSubmit
                                                    { fields = formDataThing.fields |> Maybe.withDefault fields
                                                    , action = formDataThing.action
                                                    , method =
                                                        case formDataThing.method of
                                                            Internal.FieldEvent.Get ->
                                                                Get

                                                            Internal.FieldEvent.Post ->
                                                                Post
                                                    , parsed =
                                                        case parsed of
                                                            Just justParsed ->
                                                                if Dict.isEmpty errors then
                                                                    Valid justParsed

                                                                else
                                                                    Invalid (Just justParsed) errors

                                                            Nothing ->
                                                                Invalid Nothing errors
                                                    }
                                            )
                            in
                            Internal.FieldEvent.Submit formDataThing maybeFormMsg
                                |> formState.toMsg
                        )
                    |> StyledAttr.fromUnstyled
               ]
            ++ attrs
        )
        ((hiddenInputs ++ children) |> List.map (Html.Styled.map (Internal.FieldEvent.UserMsg >> formState.toMsg)))


helperValues :
    Options error parsed input mappedMsg
    -> (List (Html.Attribute mappedMsg) -> view)
    ->
        { submitting : Bool
        , state : Model
        , toMsg : Msg mappedMsg -> mappedMsg
        }
    ->
        Form
            error
            { combine : Form.Validation.Validation error parsed field constraints
            , view : Context error input -> List view
            }
            parsed
            input
    -> { hiddenInputs : List view, children : List view, isValid : Bool, parsed : Maybe parsed, fields : List ( String, String ), errors : Dict String (List error) }
helperValues options_ toHiddenInput formState (Internal.Form.Form fieldDefinitions parser toInitialValues) =
    let
        initialValues : Dict String Form.FieldState
        initialValues =
            toInitialValues options_.input
                |> List.filterMap
                    (\( key, maybeValue ) ->
                        maybeValue
                            |> Maybe.map
                                (\value ->
                                    ( key, { value = value, status = Form.FieldStatus.notVisited } )
                                )
                    )
                |> Dict.fromList

        part2 : Dict String Form.FieldState
        part2 =
            formState.state
                |> Dict.get options_.id
                |> Maybe.withDefault
                    (options_.serverResponse
                        |> Maybe.andThen (.persisted >> .fields)
                        |> Maybe.map
                            (\fields ->
                                { fields =
                                    fields
                                        |> List.map (Tuple.mapSecond (\value -> { value = value, status = Form.FieldStatus.notVisited }))
                                        |> Dict.fromList
                                , submitAttempted = True
                                }
                            )
                        |> Maybe.withDefault initFormState
                    )
                |> .fields

        fullFormState : Dict String Form.FieldState
        fullFormState =
            initialValues
                |> Dict.union part2

        parsed :
            { result : ( Form.Validation.Validation error parsed field constraints, Dict String (List error) )
            , isMatchCandidate : Bool
            , view : Context error input -> List view
            }
        parsed =
            { isMatchCandidate = parsed1.isMatchCandidate
            , view = parsed1.combineAndView.view
            , result = ( parsed1.combineAndView.combine, parsed1.result )
            }

        parsed1 :
            { result : Dict String (List error)
            , isMatchCandidate : Bool
            , combineAndView : { combine : Form.Validation.Validation error parsed field constraints, view : Context error input -> List view }
            }
        parsed1 =
            parser (Just options_.input) thisFormState

        withoutServerErrors : Form.Validation.Validation error parsed named constraints
        withoutServerErrors =
            parsed |> mergeResults

        withServerErrors : Form.Validation.Validation error parsed named constraints
        withServerErrors =
            mergeResults
                { parsed
                    | result =
                        parsed.result
                            |> Tuple.mapSecond
                                (\errors1 ->
                                    mergeErrors errors1
                                        (options_.serverResponse
                                            |> Maybe.andThen (.persisted >> .clientSideErrors)
                                            |> Maybe.withDefault Dict.empty
                                        )
                                )
                }

        thisFormState : FormState
        thisFormState =
            formState.state
                |> Dict.get options_.id
                |> Maybe.withDefault
                    (options_.serverResponse
                        |> Maybe.andThen (.persisted >> .fields)
                        |> Maybe.map
                            (\fields ->
                                { fields =
                                    fields
                                        |> List.map (Tuple.mapSecond (\value -> { value = value, status = Form.FieldStatus.notVisited }))
                                        |> Dict.fromList
                                , submitAttempted = True
                                }
                            )
                        |> Maybe.withDefault initSingle
                    )
                |> (\state -> { state | fields = fullFormState })

        rawFields : List ( String, String )
        rawFields =
            fullFormState |> Dict.toList |> List.map (Tuple.mapSecond .value)

        context : Context error input
        context =
            { errors =
                withServerErrors
                    |> unwrapValidation
                    |> Tuple.second
                    |> Errors
            , submitting = formState.submitting
            , submitAttempted = thisFormState.submitAttempted
            , input = options_.input
            }

        children : List view
        children =
            parsed.view context

        hiddenInputs : List view
        hiddenInputs =
            fieldDefinitions
                |> List.filterMap
                    (\( name, fieldDefinition ) ->
                        case fieldDefinition of
                            Internal.Form.HiddenField ->
                                [ Attr.name name
                                , Attr.type_ "hidden"
                                , Attr.value
                                    (initialValues
                                        |> Dict.get name
                                        |> Maybe.map .value
                                        |> Maybe.withDefault ""
                                    )
                                ]
                                    |> toHiddenInput
                                    |> Just

                            Internal.Form.RegularField ->
                                Nothing
                    )

        isValid : Bool
        isValid =
            case withoutServerErrors of
                Validation _ _ ( Just _, errors ) ->
                    Dict.isEmpty errors

                _ ->
                    False

        ( maybeParsed, errorsDict ) =
            case withoutServerErrors of
                Validation _ _ ( parsedValue, errors ) ->
                    ( parsedValue, errors )
    in
    { hiddenInputs = hiddenInputs
    , children = children
    , isValid = isValid
    , parsed = maybeParsed
    , fields = rawFields
    , errors = errorsDict
    }


initSingle : FormState
initSingle =
    { fields = Dict.empty
    , submitAttempted = False
    }


{-| -}
type alias DoneForm error parsed input view =
    Form
        error
        { combine : Combined error parsed
        , view : Context error input -> view
        }
        parsed
        input


{-| -}
type alias HtmlForm error parsed input msg =
    Form
        error
        { combine : Combined error parsed
        , view : Context error input -> List (Html msg)
        }
        parsed
        input


{-| -}
type alias StyledHtmlForm error parsed input msg =
    Form
        error
        { combine : Combined error parsed
        , view : Context error input -> List (Html.Styled.Html msg)
        }
        parsed
        input


{-| -}
type alias Form error combineAndView parsed input =
    Internal.Form.Form error combineAndView parsed input


{-| -}
addErrorsInternal : String -> List error -> Dict String (List error) -> Dict String (List error)
addErrorsInternal name newErrors allErrors =
    allErrors
        |> Dict.update name
            (\errors ->
                Just (newErrors ++ (errors |> Maybe.withDefault []))
            )


{-| -}
type alias Msg msg =
    Internal.FieldEvent.Msg msg


{-| -}
mapMsg : (msg -> msgMapped) -> Msg msg -> Msg msgMapped
mapMsg mapFn msg =
    case msg of
        Internal.FieldEvent.UserMsg userMsg ->
            Internal.FieldEvent.UserMsg (mapFn userMsg)

        Internal.FieldEvent.FormFieldEvent fieldEvent ->
            Internal.FieldEvent.FormFieldEvent fieldEvent

        Internal.FieldEvent.Submit formData maybeMsg ->
            Internal.FieldEvent.Submit formData (maybeMsg |> Maybe.map mapFn)


{-| -}
type alias Model =
    Dict String FormState


{-| -}
init : Model
init =
    Dict.empty


{-| -}
update : Msg msg -> Model -> ( Model, Cmd msg )
update formMsg formModel =
    case formMsg of
        Internal.FieldEvent.UserMsg myMsg ->
            ( formModel
            , Task.succeed myMsg |> Task.perform identity
            )

        Internal.FieldEvent.FormFieldEvent value ->
            ( updateInternal value formModel
            , Cmd.none
            )

        Internal.FieldEvent.Submit formData maybeMsg ->
            ( setSubmitAttempted
                (formData.id |> Maybe.withDefault "form")
                formModel
            , maybeMsg
                |> Maybe.map (\userMsg -> Task.succeed userMsg |> Task.perform identity)
                |> Maybe.withDefault Cmd.none
            )


{-| -}
updateInternal : FieldEvent -> Model -> Model
updateInternal fieldEvent pageFormState =
    --if Dict.isEmpty pageFormState then
    --    -- TODO get all initial field values
    --    pageFormState
    --
    --else
    pageFormState
        |> Dict.update fieldEvent.formId
            (\previousValue_ ->
                let
                    previousValue : FormState
                    previousValue =
                        previousValue_
                            |> Maybe.withDefault initSingle
                in
                previousValue
                    |> updateForm fieldEvent
                    |> Just
            )


{-| -}
updateForm : FieldEvent -> FormState -> FormState
updateForm fieldEvent formState =
    { formState
        | fields =
            formState.fields
                |> Dict.update fieldEvent.name
                    (\previousValue_ ->
                        let
                            previousValue : Form.FieldState
                            previousValue =
                                previousValue_
                                    |> Maybe.withDefault { value = fieldEvent.value, status = Form.FieldStatus.notVisited }
                        in
                        (case fieldEvent.event of
                            InputEvent newValue ->
                                { previousValue
                                    | value = newValue
                                    , status = previousValue.status |> increaseStatusTo Form.FieldStatus.changed
                                }

                            FocusEvent ->
                                { previousValue | status = previousValue.status |> increaseStatusTo Form.FieldStatus.focused }

                            BlurEvent ->
                                { previousValue | status = previousValue.status |> increaseStatusTo Form.FieldStatus.blurred }
                        )
                            |> Just
                    )
    }


setSubmitAttempted : String -> Model -> Model
setSubmitAttempted fieldId pageFormState =
    pageFormState
        |> Dict.update fieldId
            (\maybeForm ->
                case maybeForm of
                    Just formState ->
                        Just { formState | submitAttempted = True }

                    Nothing ->
                        Just { initSingle | submitAttempted = True }
            )


{-| -}
increaseStatusTo : FieldStatus -> FieldStatus -> FieldStatus
increaseStatusTo increaseTo currentStatus =
    if statusRank increaseTo > statusRank currentStatus then
        increaseTo

    else
        currentStatus


{-| -}
statusRank : FieldStatus -> Int
statusRank status =
    status


{-| -}
type alias Options error parsed input msg =
    -- TODO have a way to override path?
    -- TODO move method from Form options to here
    --path : Path
    { id : String
    , method : Method
    , input : input
    , onSubmit :
        Maybe
            ({ fields : List ( String, String ), method : Method, action : String, parsed : Validated error parsed }
             -> msg
            )
    , serverResponse : Maybe (ServerResponse error)
    }


{-| -}
options : String -> Options error parsed () msg
options id =
    { id = id
    , method = Post
    , input = ()
    , onSubmit = Nothing
    , serverResponse = Nothing
    }


{-| -}
withServerResponse : Maybe (ServerResponse error) -> Options error parsed input msg -> Options error parsed input msg
withServerResponse serverResponse options_ =
    { options_ | serverResponse = serverResponse }


{-| -}
withInput : input -> Options error parsed () msg -> Options error parsed input msg
withInput input options_ =
    { id = options_.id
    , input = input
    , onSubmit = options_.onSubmit
    , serverResponse = options_.serverResponse
    , method = options_.method
    }


{-| -}
withOnSubmit : ({ fields : List ( String, String ), method : Method, action : String, parsed : Validated error parsed } -> msg) -> Options error parsed input oldMsg -> Options error parsed input msg
withOnSubmit onSubmit options_ =
    { id = options_.id
    , input = options_.input
    , onSubmit = Just onSubmit
    , serverResponse = options_.serverResponse
    , method = options_.method
    }


{-| -}
type Method
    = Get
    | Post


{-| The default Method from `options` is `Post` since that is the most common. The `Get` Method for form submissions will add the form fields as a query string and navigate to that route using a GET.
You will need to progressively enhance your onSubmit to simulate this browser behavior if you want something similar, or use a framework that has this simulation built in like `elm-pages`.
-}
withGetMethod : Options error parsed input msg -> Options error parsed input msg
withGetMethod options_ =
    { options_ | method = Get }


{-| -}
methodToString : Method -> String
methodToString method =
    case method of
        Get ->
            "GET"

        Post ->
            "POST"
