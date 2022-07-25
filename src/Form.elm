module Form exposing
    ( Form, HtmlForm, StyledHtmlForm
    , init
    , field, hiddenField, hiddenKind
    , Context
    , renderHtml, renderStyledHtml
    , FinalForm, withGetMethod, toDynamicTransition, toDynamicFetcher
    , Errors, errorsForField
    , parse, runOneOfServerSide, runServerSide, runServerSideWithoutServerValidations
    , dynamic
    , runOneOfServerSideWithServerValidations
    , AppContext
    -- subGroup
    )

{-| One of the core features of elm-pages is helping you manage form data end-to-end, including

  - Presenting the HTML form with its fields
  - Maintaining client-side form state
  - Showing validation errors on the client-side
  - Receiving a form submission on the server-side
  - Using the exact same client-side validations on the server-side
  - Letting you run server-only Validations with DataSource's (things like checking for a unique username)

Because elm-pages is a framework, it has its own internal Model and Msg's. That means you, the user,
can offload some of the responsibility to elm-pages and build an interactive form with real-time
client-side state and validation errors without wiring up your own Model and Msg's to manage that
state. You define the source of truth for your form (how to parse it into data or errors), and
elm-pages manages the state.

Let's look at a sign-up form example.


### Step 1 - Define the Form

What to look for:

**The field declarations**

Below the `Form.init` call you will find all of the form's fields declared with

    |> Form.field ...

These are the form's field declarations.

These fields each have individual validations. For example, `|> Field.required ...` means we'll get a validation
error if that field is empty (similar for checking the minimum password length).

There will be a corresponding parameter in the function we pass in to `Form.init` for every
field declaration (in this example, `\email password passwordConfirmation -> ...`).

**The `combine` validation**

In addition to the validation errors that individual fields can have independently (like
required fields or minimum password length), we can also do _dependent validations_.

We use the [`Form.Validation`](Form-Validation) module to take each individual field and combine
them into a type and/or errors.

**The `view`**

Totally customizable. Uses [`Form.FieldView`](Form-FieldView) to render all of the fields declared.

    import DataSource exposing (DataSource)
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
        Form.init
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
                            [ if info.isTransitioning then
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
        Form.Context String data
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
                |> Form.toDynamicTransition "login"
                |> Form.renderHtml [] Nothing app ()
            ]
        }


### Step 3 - Handle Server-Side Form Submissions

    action : RouteParams -> Request.Parser (DataSource (Response ActionData ErrorPage))
    action routeParams =
        Request.formDataWithoutServerValidation [ signupForm ]
            |> Request.map
                (\signupResult ->
                    case signupResult of
                        Ok newUser ->
                            newUser
                                |> myCreateUserDataSource
                                |> DataSource.map
                                    (\() ->
                                        -- redirect to the home page
                                        -- after successful sign-up
                                        Route.redirectTo Route.Index
                                    )

                        Err _ ->
                            Route.redirectTo Route.Login
                                |> DataSource.succeed
                )

    myCreateUserDataSource : DataSource ()
    myCreateUserDataSource =
        DataSource.fail
            "TODO - make a database call to create a new user"


## Building a Form Parser

@docs Form, HtmlForm, StyledHtmlForm

@docs init


## Adding Fields

@docs field, hiddenField, hiddenKind


## View Functions

@docs Context


## Rendering Forms

@docs renderHtml, renderStyledHtml

@docs FinalForm, withGetMethod, toDynamicTransition, toDynamicFetcher


## Showing Errors

@docs Errors, errorsForField


## Running Parsers

@docs parse, runOneOfServerSide, runServerSide, runServerSideWithoutServerValidations


## Dynamic Fields

@docs dynamic


## Work-In-Progress

@docs runOneOfServerSideWithServerValidations

@docs AppContext

-}

import DataSource exposing (DataSource)
import Dict exposing (Dict)
import Form.Field as Field exposing (Field(..))
import Form.FieldView
import Form.Validation as Validation exposing (Combined, Validation)
import Html exposing (Html)
import Html.Attributes as Attr
import Html.Lazy
import Html.Styled
import Html.Styled.Attributes as StyledAttr
import Html.Styled.Lazy
import Pages.FormState as Form exposing (FormState)
import Pages.Internal.Form exposing (Validation(..))
import Pages.Msg
import Pages.Transition



--{-| -}
--type
--    ParseResult error decoded
--    -- TODO parse into both errors AND a decoded value
--    = Success decoded
--    | DecodedWithErrors (Dict String (List error)) decoded
--    | DecodeFailure (Dict String (List error))


{-| -}
initFormState : FormState
initFormState =
    { fields = Dict.empty
    , submitAttempted = False
    }


{-| -}
type alias Context error data =
    { errors : Errors error
    , isTransitioning : Bool
    , submitAttempted : Bool
    , data : data
    }


{-| -}
init : combineAndView -> Form String combineAndView data
init combineAndView =
    Form []
        (\_ _ ->
            { result = Dict.empty
            , combineAndView = combineAndView
            , serverValidations = DataSource.succeed []
            }
        )
        (\_ -> [])


{-| -}
dynamic :
    (decider
     ->
        Form
            error
            { combine : Validation error parsed named constraints1
            , view : subView
            }
            data
    )
    ->
        Form
            error
            --((decider -> Validation error parsed named) -> combined)
            ({ combine : decider -> Validation error parsed named constraints1
             , view : decider -> subView
             }
             -> combineAndView
            )
            data
    ->
        Form
            error
            combineAndView
            data
dynamic forms formBuilder =
    Form []
        (\maybeData formState ->
            let
                toParser :
                    decider
                    ->
                        { result : Dict String (List error)
                        , combineAndView : { combine : Validation error parsed named constraints1, view : subView }
                        , serverValidations : DataSource (List ( String, List error ))
                        }
                toParser decider =
                    case forms decider of
                        Form _ parseFn _ ->
                            -- TODO need to include hidden form fields from `definitions` (should they be automatically rendered? Does that mean the view type needs to be hardcoded?)
                            parseFn maybeData formState

                myFn :
                    { result : Dict String (List error)
                    , combineAndView : combineAndView
                    , serverValidations : DataSource (List ( String, List error ))
                    }
                myFn =
                    let
                        newThing :
                            { result : Dict String (List error)
                            , combineAndView : { combine : decider -> Validation error parsed named constraints1, view : decider -> subView } -> combineAndView
                            , serverValidations : DataSource (List ( String, List error ))
                            }
                        newThing =
                            case formBuilder of
                                Form _ parseFn _ ->
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
                    , serverValidations = DataSource.succeed [] -- TODO how do I combine them here?
                    }
            in
            myFn
        )
        (\_ -> [])



--{-| -}
--subGroup :
--    Form error ( Maybe parsed, Dict String (List error) ) data (Context error data -> subView)
--    ->
--        Form
--            error
--            ({ value : parsed } -> combined)
--            data
--            (Context error data -> (subView -> combinedView))
--    -> Form error combined data (Context error data -> combinedView)
--subGroup forms formBuilder =
--    Form []
--        (\maybeData formState ->
--            let
--                toParser : { result : ( Maybe ( Maybe parsed, Dict String (List error) ), Dict String (List error) ), view : Context error data -> subView }
--                toParser =
--                    case forms of
--                        Form definitions parseFn toInitialValues ->
--                            -- TODO need to include hidden form fields from `definitions` (should they be automatically rendered? Does that mean the view type needs to be hardcoded?)
--                            parseFn maybeData formState
--
--                myFn :
--                    { result : ( Maybe combined, Dict String (List error) )
--                    , view : Context error data -> combinedView
--                    }
--                myFn =
--                    let
--                        deciderToParsed : ( Maybe parsed, Dict String (List error) )
--                        deciderToParsed =
--                            toParser |> mergeResults
--
--                        newThing : { result : ( Maybe ({ value : parsed } -> combined), Dict String (List error) ), view : Context error data -> subView -> combinedView }
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


{-| -}
field :
    String
    -> Field error parsed data kind constraints
    -> Form error (Validation.Field error parsed kind -> combineAndView) data
    -> Form error combineAndView data
field name (Field fieldParser kind) (Form definitions parseFn toInitialValues) =
    Form
        (( name, RegularField )
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
                            ( Maybe.map2 (|>) maybeData fieldParser.initialValue, Form.NotVisited )

                thing : Pages.Internal.Form.ViewField kind
                thing =
                    { value = rawFieldValue
                    , status = fieldStatus
                    , kind = ( kind, fieldParser.properties )
                    }

                parsedField : Validation.Field error parsed kind
                parsedField =
                    Pages.Internal.Form.Validation (Just thing) (Just name) ( maybeParsed, Dict.empty )

                myFn :
                    { result : Dict String (List error)
                    , combineAndView : Validation.Field error parsed kind -> combineAndView
                    , serverValidations : DataSource (List ( String, List error ))
                    }
                    ->
                        { result : Dict String (List error)
                        , combineAndView : combineAndView
                        , serverValidations : DataSource (List ( String, List error ))
                        }
                myFn soFar =
                    let
                        serverValidationsForField : DataSource ( String, List error )
                        serverValidationsForField =
                            fieldParser.serverValidation rawFieldValue
                                |> DataSource.map (Tuple.pair name)

                        validationField : Validation.Field error parsed kind
                        validationField =
                            parsedField
                    in
                    { result =
                        soFar.result
                            |> addErrorsInternal name errors
                    , combineAndView =
                        soFar.combineAndView validationField
                    , serverValidations =
                        DataSource.map2 (::)
                            serverValidationsForField
                            soFar.serverValidations
                    }
            in
            formState
                |> parseFn maybeData
                |> myFn
        )
        (\data ->
            case fieldParser.initialValue of
                Just toInitialValue ->
                    ( name, toInitialValue data )
                        :: toInitialValues data

                Nothing ->
                    toInitialValues data
        )


{-| -}
hiddenField :
    String
    -> Field error parsed data kind constraints
    -> Form error (Validation.Field error parsed Form.FieldView.Hidden -> combineAndView) data
    -> Form error combineAndView data
hiddenField name (Field fieldParser _) (Form definitions parseFn toInitialValues) =
    Form
        (( name, HiddenField )
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
                            ( Maybe.map2 (|>) maybeData fieldParser.initialValue, Form.NotVisited )

                thing : Pages.Internal.Form.ViewField Form.FieldView.Hidden
                thing =
                    { value = rawFieldValue
                    , status = fieldStatus
                    , kind = ( Form.FieldView.Hidden, fieldParser.properties )
                    }

                parsedField : Validation.Field error parsed Form.FieldView.Hidden
                parsedField =
                    Pages.Internal.Form.Validation (Just thing) (Just name) ( maybeParsed, Dict.empty )

                myFn :
                    { result : Dict String (List error)
                    , combineAndView : Validation.Field error parsed Form.FieldView.Hidden -> combineAndView
                    , serverValidations : DataSource (List ( String, List error ))
                    }
                    ->
                        { result : Dict String (List error)
                        , combineAndView : combineAndView
                        , serverValidations : DataSource (List ( String, List error ))
                        }
                myFn soFar =
                    let
                        serverValidationsForField : DataSource ( String, List error )
                        serverValidationsForField =
                            fieldParser.serverValidation rawFieldValue
                                |> DataSource.map (Tuple.pair name)

                        validationField : Validation.Field error parsed Form.FieldView.Hidden
                        validationField =
                            parsedField
                    in
                    { result =
                        soFar.result
                            |> addErrorsInternal name errors
                    , combineAndView =
                        soFar.combineAndView validationField
                    , serverValidations =
                        DataSource.map2 (::)
                            serverValidationsForField
                            soFar.serverValidations
                    }
            in
            formState
                |> parseFn maybeData
                |> myFn
        )
        (\data ->
            case fieldParser.initialValue of
                Just toInitialValue ->
                    ( name, toInitialValue data )
                        :: toInitialValues data

                Nothing ->
                    toInitialValues data
        )


{-| -}
hiddenKind :
    ( String, String )
    -> error
    -> Form error combineAndView data
    -> Form error combineAndView data
hiddenKind ( name, value ) error_ (Form definitions parseFn toInitialValues) =
    let
        (Field fieldParser _) =
            Field.exactValue value error_
    in
    Form
        (( name, HiddenField )
            :: definitions
        )
        (\maybeData formState ->
            let
                ( _, errors ) =
                    fieldParser.decode rawFieldValue

                rawFieldValue : Maybe String
                rawFieldValue =
                    case formState.fields |> Dict.get name of
                        Just info ->
                            Just info.value

                        Nothing ->
                            Maybe.map2 (|>) maybeData fieldParser.initialValue

                myFn :
                    { result : Dict String (List error)
                    , combineAndView : combineAndView
                    , serverValidations : DataSource (List ( String, List error ))
                    }
                    ->
                        { result : Dict String (List error)
                        , combineAndView : combineAndView
                        , serverValidations : DataSource (List ( String, List error ))
                        }
                myFn soFar =
                    let
                        serverValidationsForField : DataSource ( String, List error )
                        serverValidationsForField =
                            fieldParser.serverValidation rawFieldValue
                                |> DataSource.map (Tuple.pair name)
                    in
                    { result =
                        soFar.result
                            |> addErrorsInternal name errors
                    , combineAndView = soFar.combineAndView
                    , serverValidations =
                        DataSource.map2 (::)
                            serverValidationsForField
                            soFar.serverValidations
                    }
            in
            formState
                |> parseFn maybeData
                |> myFn
        )
        (\data ->
            case fieldParser.initialValue of
                Just toInitialValue ->
                    ( name, toInitialValue data )
                        :: toInitialValues data

                Nothing ->
                    toInitialValues data
        )


{-| -}
type Errors error
    = Errors (Dict String (List error))


{-| -}
errorsForField : Validation.Field error parsed kind -> Errors error -> List error
errorsForField field_ (Errors errorsDict) =
    errorsDict
        |> Dict.get (Validation.fieldName field_)
        |> Maybe.withDefault []


{-| -}
type alias AppContext app =
    { app
        | --, sharedData : Shared.Data
          --, routeParams : routeParams
          --, path : Path
          --, action : Maybe action
          --, submit :
          --    { fields : List ( String, String ), headers : List ( String, String ) }
          --    -> Pages.Fetcher.Fetcher (Result Http.Error action)
          transition : Maybe Pages.Transition.Transition
        , fetchers : List Pages.Transition.FetcherState
        , pageFormState : Dict String FormState
    }


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


mergeResultsDataSource :
    { a
        | result : ( Validation error parsed named constraints, Dict String (List error) )
        , serverValidations : DataSource (List ( String, List error ))
    }
    -> ( Maybe parsed, DataSource (Dict String (List error)) )
mergeResultsDataSource parsed =
    case parsed.result of
        ( Pages.Internal.Form.Validation _ _ ( parsedThing, combineErrors ), individualFieldErrors ) ->
            ( parsedThing
            , parsed.serverValidations
                |> DataSource.map
                    (\serverValidationErrorsList ->
                        let
                            serverValidationErrors : Dict String (List error)
                            serverValidationErrors =
                                serverValidationErrorsList
                                    |> List.foldl
                                        (\( key, errorsForKey ) soFar ->
                                            soFar
                                                |> Dict.update key
                                                    (\maybeList ->
                                                        maybeList
                                                            |> Maybe.withDefault []
                                                            |> List.append errorsForKey
                                                            |> Just
                                                    )
                                        )
                                        Dict.empty
                        in
                        mergeErrors
                            combineErrors
                            individualFieldErrors
                            |> mergeErrors serverValidationErrors
                    )
            )



--resultsToDict : List a -> Dict String (List error)
--resultsToDict list =
--    list
--        |> List.foldl
--            (\( key, errorsForKey ) soFar ->
--                soFar
--                    |> Dict.update key
--                        (\maybeList ->
--                            maybeList
--                                |> Maybe.withDefault []
--                                |> List.append errorsForKey
--                                |> Just
--                        )
--            )
--            Dict.empty


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
    -> AppContext app
    -> data
    -> Form error { info | combine : Validation error parsed named constraints } data
    -> ( Maybe parsed, Dict String (List error) )
parse formId app data (Form _ parser _) =
    -- TODO Get transition context from `app` so you can check if the current form is being submitted
    -- TODO either as a transition or a fetcher? Should be easy enough to check for the `id` on either of those?
    let
        parsed :
            { result : Dict String (List error)
            , combineAndView : { info | combine : Validation error parsed named constraints }
            , serverValidations : DataSource (List ( String, List error ))
            }
        parsed =
            parser (Just data) thisFormState

        thisFormState : FormState
        thisFormState =
            app.pageFormState
                |> Dict.get formId
                |> Maybe.withDefault initFormState
    in
    { result = ( parsed.combineAndView.combine, parsed.result )
    , serverValidations = parsed.serverValidations
    }
        |> mergeResults
        |> unwrapValidation


insertIfNonempty : comparable -> List value -> Dict comparable (List value) -> Dict comparable (List value)
insertIfNonempty key values dict =
    if values |> List.isEmpty then
        dict

    else
        dict
            |> Dict.insert key values


{-| -}
runServerSide :
    List ( String, String )
    -> Form error { all | combine : Validation error parsed kind constraints } data
    -> ( Maybe parsed, DataSource (Dict String (List error)) )
runServerSide rawFormData (Form _ parser _) =
    let
        parsed :
            { result : Dict String (List error)
            , combineAndView : { all | combine : Validation error parsed kind constraints }
            , serverValidations : DataSource (List ( String, List error ))
            }
        parsed =
            parser Nothing thisFormState

        thisFormState : FormState
        thisFormState =
            { initFormState
                | fields =
                    rawFormData
                        |> List.map
                            (Tuple.mapSecond
                                (\value ->
                                    { value = value
                                    , status = Form.NotVisited
                                    }
                                )
                            )
                        |> Dict.fromList
            }
    in
    { result = ( parsed.combineAndView.combine, parsed.result )
    , serverValidations = parsed.serverValidations
    }
        |> mergeResultsDataSource


{-| -}
runServerSideWithoutServerValidations :
    List ( String, String )
    -> Form error { all | combine : Validation error parsed kind constraints } data
    -> ( Maybe parsed, Dict String (List error) )
runServerSideWithoutServerValidations rawFormData (Form _ parser _) =
    let
        parsed :
            { result : Dict String (List error)
            , combineAndView : { all | combine : Validation error parsed kind constraints }
            , serverValidations : DataSource (List ( String, List error ))
            }
        parsed =
            parser Nothing thisFormState

        thisFormState : FormState
        thisFormState =
            { initFormState
                | fields =
                    rawFormData
                        |> List.map
                            (Tuple.mapSecond
                                (\value ->
                                    { value = value
                                    , status = Form.NotVisited
                                    }
                                )
                            )
                        |> Dict.fromList
            }
    in
    { result = ( parsed.combineAndView.combine, parsed.result )
    , serverValidations = parsed.serverValidations
    }
        |> mergeResults
        |> unwrapValidation


unwrapValidation : Validation error parsed named constraints -> ( Maybe parsed, Dict String (List error) )
unwrapValidation (Pages.Internal.Form.Validation viewField name ( maybeParsed, errors )) =
    ( maybeParsed, errors )


{-| -}
runOneOfServerSide :
    List ( String, String )
    ->
        List
            (Form
                error
                { all | combine : Validation error parsed kind constraints }
                data
            )
    -> ( Maybe parsed, Dict String (List error) )
runOneOfServerSide rawFormData parsers =
    case parsers of
        firstParser :: remainingParsers ->
            let
                thing : ( Maybe parsed, List ( String, List error ) )
                thing =
                    runServerSideWithoutServerValidations rawFormData firstParser
                        |> Tuple.mapSecond
                            (\errors ->
                                errors
                                    |> Dict.toList
                                    |> List.filter (Tuple.second >> List.isEmpty >> not)
                            )
            in
            case thing of
                ( Just parsed, [] ) ->
                    ( Just parsed, Dict.empty )

                _ ->
                    runOneOfServerSide rawFormData remainingParsers

        [] ->
            -- TODO need to pass errors
            ( Nothing, Dict.empty )


{-| -}
runOneOfServerSideWithServerValidations :
    List ( String, String )
    ->
        List
            (Form
                error
                { all | combine : Validation error parsed kind constraints }
                data
            )
    -> ( Maybe parsed, DataSource (Dict String (List error)) )
runOneOfServerSideWithServerValidations rawFormData parsers =
    case parsers of
        firstParser :: remainingParsers ->
            let
                thing : ( Maybe parsed, DataSource (Dict String (List error)) )
                thing =
                    runServerSide rawFormData firstParser
            in
            case thing of
                -- TODO should it try to look for anything that parses with no errors, or short-circuit if something parses regardless of errors?
                ( Just _, _ ) ->
                    thing

                _ ->
                    runOneOfServerSideWithServerValidations rawFormData remainingParsers

        [] ->
            -- TODO need to pass errors
            ( Nothing, DataSource.succeed Dict.empty )


{-| -}
renderHtml :
    List (Html.Attribute (Pages.Msg.Msg msg))
    ->
        Maybe
            { fields : List ( String, String )
            , errors : Dict String (List error)
            }
    -> AppContext app
    -> data
    ->
        FinalForm
            error
            (Validation error parsed named constraints)
            data
            (Context error data
             -> List (Html (Pages.Msg.Msg msg))
            )
    -> Html (Pages.Msg.Msg msg)
renderHtml attrs maybe app data (FinalForm options a b c) =
    Html.Lazy.lazy6 renderHelper attrs maybe options app data (FormInternal a b c)


{-| -}
type FinalForm error parsed data view
    = FinalForm
        { submitStrategy : SubmitStrategy
        , method : Method
        , name : Maybe String
        }
        (List ( String, FieldDefinition ))
        (Maybe data
         -> FormState
         ->
            { result :
                ( parsed
                , Dict String (List error)
                )
            , view : view
            , serverValidations : DataSource (List ( String, List error ))
            }
        )
        (data -> List ( String, String ))


{-| -}
toDynamicFetcher :
    String
    ->
        Form
            error
            { combine : Validation error parsed field constraints
            , view : Context error data -> view
            }
            data
    ->
        FinalForm
            error
            (Validation error parsed field constraints)
            data
            (Context error data -> view)
toDynamicFetcher name (Form a b c) =
    let
        options =
            { submitStrategy = FetcherStrategy
            , method = Post
            , name = Just name
            }

        transformB :
            (Maybe data
             -> FormState
             ->
                { result : Dict String (List error)
                , combineAndView :
                    { combine : Validation error parsed field constraints
                    , view : Context error data -> view
                    }
                , serverValidations : DataSource (List ( String, List error ))
                }
            )
            ->
                (Maybe data
                 -> FormState
                 ->
                    { result :
                        ( Validation error parsed field constraints
                        , Dict String (List error)
                        )
                    , view : Context error data -> view
                    , serverValidations : DataSource (List ( String, List error ))
                    }
                )
        transformB rawB =
            \maybeData formState ->
                let
                    foo :
                        { result : Dict String (List error)
                        , combineAndView :
                            { combine : Validation error parsed field constraints
                            , view : Context error data -> view
                            }
                        , serverValidations : DataSource (List ( String, List error ))
                        }
                    foo =
                        rawB maybeData formState
                in
                { result = ( foo.combineAndView.combine, foo.result )
                , view = foo.combineAndView.view
                , serverValidations = foo.serverValidations
                }
    in
    FinalForm options a (transformB b) c


{-| -}
toDynamicTransition :
    String
    ->
        Form
            error
            { combine : Validation error parsed field constraints
            , view : Context error data -> view
            }
            data
    ->
        FinalForm
            error
            (Validation error parsed field constraints)
            data
            (Context error data -> view)
toDynamicTransition name (Form a b c) =
    let
        options =
            { submitStrategy = TransitionStrategy
            , method = Post
            , name = Just name
            }

        transformB :
            (Maybe data
             -> FormState
             ->
                { result : Dict String (List error)
                , combineAndView :
                    { combine : Validation error parsed field constraints
                    , view : Context error data -> view
                    }
                , serverValidations : DataSource (List ( String, List error ))
                }
            )
            ->
                (Maybe data
                 -> FormState
                 ->
                    { result :
                        ( Validation error parsed field constraints
                        , Dict String (List error)
                        )
                    , view : Context error data -> view
                    , serverValidations : DataSource (List ( String, List error ))
                    }
                )
        transformB rawB =
            \maybeData formState ->
                let
                    foo :
                        { result : Dict String (List error)
                        , combineAndView :
                            { combine : Validation error parsed field constraints
                            , view : Context error data -> view
                            }
                        , serverValidations : DataSource (List ( String, List error ))
                        }
                    foo =
                        rawB maybeData formState
                in
                { result = ( foo.combineAndView.combine, foo.result )
                , view = foo.combineAndView.view
                , serverValidations = foo.serverValidations
                }
    in
    FinalForm options a (transformB b) c


{-| -}
withGetMethod : FinalForm error parsed data view -> FinalForm error parsed data view
withGetMethod (FinalForm options a b c) =
    FinalForm { options | method = Get } a b c


{-| -}
renderStyledHtml :
    List (Html.Styled.Attribute (Pages.Msg.Msg msg))
    ->
        Maybe
            { fields : List ( String, String )
            , errors : Dict String (List error)
            }
    -> AppContext app
    -> data
    ->
        FinalForm
            error
            (Validation error parsed named constraints)
            data
            (Context error data
             -> List (Html.Styled.Html (Pages.Msg.Msg msg))
            )
    -> Html.Styled.Html (Pages.Msg.Msg msg)
renderStyledHtml attrs maybe app data (FinalForm options a b c) =
    Html.Styled.Lazy.lazy6 renderStyledHelper attrs maybe options app data (FormInternal a b c)


renderHelper :
    List (Html.Attribute (Pages.Msg.Msg msg))
    ->
        Maybe
            { fields : List ( String, String )
            , errors : Dict String (List error)
            }
    -> RenderOptions
    -> AppContext app
    -> data
    -> FormInternal error (Validation error parsed named constraints) data (Context error data -> List (Html (Pages.Msg.Msg msg)))
    -> Html (Pages.Msg.Msg msg)
renderHelper attrs maybe options formState data ((FormInternal fieldDefinitions parser toInitialValues) as form) =
    -- TODO Get transition context from `app` so you can check if the current form is being submitted
    -- TODO either as a transition or a fetcher? Should be easy enough to check for the `id` on either of those?
    let
        { formId, hiddenInputs, children, isValid } =
            helperValues toHiddenInput maybe options formState data form

        toHiddenInput : List (Html.Attribute (Pages.Msg.Msg msg)) -> Html (Pages.Msg.Msg msg)
        toHiddenInput hiddenAttrs =
            Html.input hiddenAttrs []
    in
    Html.form
        (Form.listeners formId
            ++ [ Attr.method (methodToString options.method)
               , Attr.novalidate True
               , case options.submitStrategy of
                    FetcherStrategy ->
                        Pages.Msg.fetcherOnSubmit formId (\_ -> isValid)

                    TransitionStrategy ->
                        Pages.Msg.submitIfValid formId (\_ -> isValid)
               ]
            ++ attrs
        )
        (hiddenInputs ++ children)


renderStyledHelper :
    List (Html.Styled.Attribute (Pages.Msg.Msg msg))
    ->
        Maybe
            { fields : List ( String, String )
            , errors : Dict String (List error)
            }
    -> RenderOptions
    -> AppContext app
    -> data
    -> FormInternal error (Validation error parsed named constraints) data (Context error data -> List (Html.Styled.Html (Pages.Msg.Msg msg)))
    -> Html.Styled.Html (Pages.Msg.Msg msg)
renderStyledHelper attrs maybe options formState data ((FormInternal fieldDefinitions parser toInitialValues) as form) =
    -- TODO Get transition context from `app` so you can check if the current form is being submitted
    -- TODO either as a transition or a fetcher? Should be easy enough to check for the `id` on either of those?
    let
        { formId, hiddenInputs, children, isValid } =
            helperValues toHiddenInput maybe options formState data form

        toHiddenInput : List (Html.Attribute (Pages.Msg.Msg msg)) -> Html.Styled.Html (Pages.Msg.Msg msg)
        toHiddenInput hiddenAttrs =
            Html.Styled.input (hiddenAttrs |> List.map StyledAttr.fromUnstyled) []
    in
    Html.Styled.form
        ((Form.listeners formId |> List.map StyledAttr.fromUnstyled)
            ++ [ StyledAttr.method (methodToString options.method)
               , StyledAttr.novalidate True
               , case options.submitStrategy of
                    FetcherStrategy ->
                        StyledAttr.fromUnstyled <|
                            Pages.Msg.fetcherOnSubmit formId (\_ -> isValid)

                    TransitionStrategy ->
                        StyledAttr.fromUnstyled <|
                            Pages.Msg.submitIfValid formId (\_ -> isValid)
               ]
            ++ attrs
        )
        (hiddenInputs ++ children)


helperValues :
    (List (Html.Attribute msg) -> view)
    ->
        Maybe
            { fields : List ( String, String )
            , errors : Dict String (List error)
            }
    -> RenderOptions
    -> AppContext app
    -> data
    ---> Form error parsed data view
    -> FormInternal error (Validation error parsed named constraints) data (Context error data -> List view)
    -> { formId : String, hiddenInputs : List view, children : List view, isValid : Bool }
helperValues toHiddenInput maybe options formState data (FormInternal fieldDefinitions parser toInitialValues) =
    let
        formId : String
        formId =
            options.name |> Maybe.withDefault ""

        initialValues : Dict String Form.FieldState
        initialValues =
            toInitialValues data
                |> List.map (Tuple.mapSecond (\value -> { value = value, status = Form.NotVisited }))
                |> Dict.fromList

        part2 : Dict String Form.FieldState
        part2 =
            formState.pageFormState
                |> Dict.get formId
                |> Maybe.withDefault
                    (maybe
                        |> Maybe.map
                            (\{ fields } ->
                                { fields =
                                    fields
                                        |> List.map (Tuple.mapSecond (\value -> { value = value, status = Form.NotVisited }))
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
            { result : ( Validation error parsed named constraints, Dict String (List error) )
            , view : Context error data -> List view
            , serverValidations : DataSource (List ( String, List error ))
            }
        parsed =
            parser (Just data) thisFormState

        merged : Validation error parsed named constraints
        merged =
            mergeResults
                { parsed
                    | result =
                        parsed.result
                            |> Tuple.mapSecond
                                (\errors1 ->
                                    mergeErrors errors1
                                        (maybe
                                            |> Maybe.map .errors
                                            |> Maybe.withDefault Dict.empty
                                        )
                                )
                }

        thisFormState : FormState
        thisFormState =
            formState.pageFormState
                |> Dict.get formId
                |> Maybe.withDefault
                    (maybe
                        |> Maybe.map
                            (\{ fields } ->
                                { fields =
                                    fields
                                        |> List.map (Tuple.mapSecond (\value -> { value = value, status = Form.NotVisited }))
                                        |> Dict.fromList
                                , submitAttempted = True
                                }
                            )
                        |> Maybe.withDefault Form.init
                    )
                |> (\state -> { state | fields = fullFormState })

        context : Context error data
        context =
            { errors =
                merged
                    |> unwrapValidation
                    |> Tuple.second
                    |> Errors
            , isTransitioning =
                case formState.transition of
                    Just _ ->
                        --let
                        --    foo =
                        --        transition.id
                        --in
                        -- TODO need to track the form's ID and check that to see if it's *this*
                        -- form that is submitting
                        --transition.todo == formId
                        True

                    Nothing ->
                        False
            , submitAttempted = thisFormState.submitAttempted
            , data = data
            }

        children =
            parsed.view context

        hiddenInputs : List view
        hiddenInputs =
            fieldDefinitions
                |> List.filterMap
                    (\( name, fieldDefinition ) ->
                        case fieldDefinition of
                            HiddenField ->
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

                            RegularField ->
                                Nothing
                    )

        isValid : Bool
        isValid =
            case merged of
                Validation _ _ ( Just _, errors ) ->
                    Dict.isEmpty errors

                _ ->
                    False
    in
    { formId = formId
    , hiddenInputs = hiddenInputs
    , children = children
    , isValid = isValid
    }


{-| -}
type alias HtmlForm error parsed data msg =
    Form
        error
        { combine : Combined error parsed
        , view : Context error data -> List (Html (Pages.Msg.Msg msg))
        }
        data


{-| -}
type alias StyledHtmlForm error parsed data msg =
    Form
        error
        { combine : Combined error parsed
        , view : Context error data -> List (Html.Styled.Html (Pages.Msg.Msg msg))
        }
        data


{-| -}
type FormInternal error parsed data view
    = FormInternal
        -- TODO for renderCustom, pass them as an argument with all hidden fields that the user must render
        (List ( String, FieldDefinition ))
        (Maybe data
         -> FormState
         ->
            { result :
                ( parsed
                , Dict String (List error)
                )
            , view : view
            , serverValidations : DataSource (List ( String, List error ))
            }
        )
        (data -> List ( String, String ))


{-| -}
type Form error combineAndView data
    = Form
        (List ( String, FieldDefinition ))
        (Maybe data
         -> FormState
         ->
            { result : Dict String (List error)
            , combineAndView : combineAndView
            , serverValidations : DataSource (List ( String, List error ))
            }
        )
        (data -> List ( String, String ))


type alias RenderOptions =
    { submitStrategy : SubmitStrategy
    , method : Method
    , name : Maybe String
    }


{-| -}
type Method
    = Post
    | Get


methodToString : Method -> String
methodToString method =
    case method of
        Post ->
            "POST"

        Get ->
            "GET"


{-| -}
type SubmitStrategy
    = FetcherStrategy
    | TransitionStrategy


{-| -}
type FieldDefinition
    = RegularField
    | HiddenField


{-| -}
addErrorsInternal : String -> List error -> Dict String (List error) -> Dict String (List error)
addErrorsInternal name newErrors allErrors =
    allErrors
        |> Dict.update name
            (\errors ->
                Just (newErrors ++ (errors |> Maybe.withDefault []))
            )
