module Form exposing
    ( Form, HtmlForm, StyledHtmlForm, DoneForm
    , Response(..)
    , init
    , field, hiddenField, hiddenKind
    , Context
    , renderHtml, renderStyledHtml
    , FinalForm, withGetMethod, toDynamicTransition, toDynamicFetcher
    , Errors, errorsForField
    , parse, runServerSide, runOneOfServerSide
    , ServerForms(..)
    , initCombined, combine, initCombinedServer, combineServer
    , dynamic
    , AppContext
    , toServerForm, withOnSubmit
    -- subGroup
    )

{-| One of the core features of elm-pages is helping you manage form data end-to-end, including

  - Presenting the HTML form with its fields
  - Maintaining client-side form state
  - Showing validation errors on the client-side
  - Receiving a form submission on the server-side
  - Using the exact same client-side validations on the server-side
  - Letting you run server-only Validations with BackendTask's (things like checking for a unique username)

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

@docs Response

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

@docs parse, runServerSide, runOneOfServerSide


## Combining Forms to Run on Server

@docs ServerForms

@docs initCombined, combine, initCombinedServer, combineServer


## Dynamic Fields

@docs dynamic

@docs AppContext


## Submission

@docs toServerForm, withOnSubmit

-}

import BackendTask exposing (BackendTask)
import Dict exposing (Dict)
import Form.Field as Field exposing (Field(..))
import Form.FieldStatus as FieldStatus exposing (FieldStatus)
import Form.FieldView
import Form.Validation as Validation exposing (Combined)
import Html exposing (Html)
import Html.Attributes as Attr
import Html.Lazy
import Html.Styled
import Html.Styled.Attributes as StyledAttr
import Html.Styled.Lazy
import Pages.FormState as Form exposing (FormState)
import Pages.Internal.Form exposing (Validation(..))
import Pages.Msg
import Pages.Transition exposing (Transition(..))
import Path exposing (Path)



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
            { combine : Validation.Validation error parsed named constraints1
            , view : subView
            }
            data
    )
    ->
        Form
            error
            --((decider -> Validation error parsed named) -> combined)
            ({ combine : decider -> Validation.Validation error parsed named constraints1
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
                        , isMatchCandidate : Bool
                        , combineAndView : { combine : Validation error parsed named constraints1, view : subView }
                        }
                toParser decider =
                    case forms decider of
                        Form _ parseFn _ ->
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
                    , isMatchCandidate = newThing.isMatchCandidate
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


{-| Declare a visible field for the form.

Use [`Form.Field`](Form-Field) to define the field and its validations.

    form =
        Form.init
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
                    -- @@@@@@ use code from here
                    fieldParser.decode rawFieldValue

                ( rawFieldValue, fieldStatus ) =
                    case formState.fields |> Dict.get name of
                        Just info ->
                            ( Just info.value, info.status )

                        Nothing ->
                            ( Maybe.map2 (|>) maybeData fieldParser.initialValue, FieldStatus.NotVisited )

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
                    , isMatchCandidate : Bool
                    }
                    ->
                        { result : Dict String (List error)
                        , combineAndView : combineAndView
                        , isMatchCandidate : Bool
                        }
                myFn soFar =
                    let
                        validationField : Validation.Field error parsed kind
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
        (\data ->
            case fieldParser.initialValue of
                Just toInitialValue ->
                    ( name, toInitialValue data )
                        :: toInitialValues data

                Nothing ->
                    toInitialValues data
        )


{-| Declare a hidden field for the form.

Unlike [`field`](#field) declarations which are rendered using [`Form.FieldView`](Form-FieldView)
functions, `hiddenField` inputs are automatically inserted into the form when you render it.

You define the field's validations the same way as for `field`, with the
[`Form.Field`](Form-Field) API.

    form =
        Form.init
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
                            ( Maybe.map2 (|>) maybeData fieldParser.initialValue, FieldStatus.NotVisited )

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
                    , isMatchCandidate : Bool
                    }
                    ->
                        { result : Dict String (List error)
                        , combineAndView : combineAndView
                        , isMatchCandidate : Bool
                        }
                myFn soFar =
                    let
                        validationField : Validation.Field error parsed Form.FieldView.Hidden
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
        (\data ->
            case fieldParser.initialValue of
                Just toInitialValue ->
                    ( name, toInitialValue data )
                        :: toInitialValues data

                Nothing ->
                    toInitialValues data
        )


{-| -}
toServerForm :
    Form
        error
        { combine : Validation.Validation error combined kind constraints
        , view : viewFn
        }
        data
    ->
        Form
            error
            { combine : Validation.Validation error (BackendTask backendTaskError (Validation.Validation error combined kind constraints)) kind constraints
            , view : viewFn
            }
            data
toServerForm (Form a b c) =
    let
        mappedB :
            Maybe data
            -> FormState
            ->
                { result : Dict String (List error)
                , isMatchCandidate : Bool
                , combineAndView :
                    { combine : Validation.Validation error (BackendTask backendTaskError (Validation.Validation error combined kind constraints)) kind constraints
                    , view : viewFn
                    }
                }
        mappedB maybeData formState =
            b maybeData formState
                |> (\thing ->
                        { result = thing.result
                        , combineAndView =
                            { combine =
                                thing.combineAndView.combine
                                    |> BackendTask.succeed
                                    |> Validation.succeed2
                            , view = thing.combineAndView.view
                            }
                        , isMatchCandidate = thing.isMatchCandidate
                        }
                   )
    in
    Form a mappedB c


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
                ( decodedValue, errors ) =
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
type alias AppContext app actionData =
    { app
        | --, sharedData : Shared.Data
          --, routeParams : routeParams
          path : Path

        --, action : Maybe action
        --, submit :
        --    { fields : List ( String, String ), headers : List ( String, String ) }
        --    -> Pages.Fetcher.Fetcher (Result Http.Error action)
        , transition : Maybe Transition
        , fetchers : Dict String (Pages.Transition.FetcherState actionData)
        , pageFormState :
            Dict String { fields : Dict String { value : String, status : FieldStatus }, submitAttempted : Bool }
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
    -> AppContext app actionData
    -> data
    -> Form error { info | combine : Validation.Validation error parsed named constraints } data
    -> ( Maybe parsed, Dict String (List error) )
parse formId app data (Form _ parser _) =
    -- TODO Get transition context from `app` so you can check if the current form is being submitted
    -- TODO either as a transition or a fetcher? Should be easy enough to check for the `id` on either of those?
    let
        parsed :
            { result : Dict String (List error)
            , isMatchCandidate : Bool
            , combineAndView : { info | combine : Validation error parsed named constraints }
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
    -> Form error (Validation.Validation error parsed kind constraints) data
    -> ( Bool, ( Maybe parsed, Dict String (List error) ) )
runServerSide rawFormData (Form _ parser _) =
    let
        parsed :
            { result : Dict String (List error)
            , isMatchCandidate : Bool
            , combineAndView : Validation error parsed kind constraints
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
                                    , status = FieldStatus.NotVisited
                                    }
                                )
                            )
                        |> Dict.fromList
            }
    in
    ( parsed.isMatchCandidate
    , { result = ( parsed.combineAndView, parsed.result )
      }
        |> mergeResults
        |> unwrapValidation
    )


unwrapValidation : Validation error parsed named constraints -> ( Maybe parsed, Dict String (List error) )
unwrapValidation (Pages.Internal.Form.Validation _ _ ( maybeParsed, errors )) =
    ( maybeParsed, errors )


{-| -}
runOneOfServerSide :
    List ( String, String )
    -> ServerForms error parsed
    -> ( Maybe parsed, Dict String (List error) )
runOneOfServerSide rawFormData forms =
    runOneOfServerSideHelp rawFormData Nothing forms


{-| -}
runOneOfServerSideHelp :
    List ( String, String )
    -> Maybe (List ( String, List error ))
    -> ServerForms error parsed
    -> ( Maybe parsed, Dict String (List error) )
runOneOfServerSideHelp rawFormData firstFoundErrors (ServerForms parsers) =
    case parsers of
        firstParser :: remainingParsers ->
            let
                ( isMatchCandidate, thing1 ) =
                    runServerSide rawFormData firstParser

                thing : ( Maybe parsed, List ( String, List error ) )
                thing =
                    thing1
                        |> Tuple.mapSecond
                            (\errors ->
                                errors
                                    |> Dict.toList
                                    |> List.filter (Tuple.second >> List.isEmpty >> not)
                            )
            in
            case ( isMatchCandidate, thing ) of
                ( True, ( Just parsed, errors ) ) ->
                    ( Just parsed, errors |> Dict.fromList )

                ( _, ( _, errors ) ) ->
                    runOneOfServerSideHelp rawFormData
                        (firstFoundErrors
                            -- TODO is this logic what we want here? Might need to think through the semantics a bit more
                            -- of which errors to parse into - could be the first errors, the last, or some other way of
                            -- having higher precedence for deciding which form should be used
                            |> Maybe.withDefault errors
                            |> Just
                        )
                        (ServerForms remainingParsers)

        [] ->
            -- TODO need to pass errors
            ( Nothing, firstFoundErrors |> Maybe.withDefault [] |> Dict.fromList )


{-| -}
renderHtml :
    List (Html.Attribute (Pages.Msg.Msg msg))
    ->
        Maybe
            { fields : List ( String, String )
            , errors : Dict String (List error)
            }
    -> AppContext app actionData
    -> data
    ->
        FinalForm
            error
            (Validation.Validation error parsed named constraints)
            data
            (Context error data
             -> List (Html (Pages.Msg.Msg msg))
            )
            msg
    -> Html (Pages.Msg.Msg msg)
renderHtml attrs maybe app data (FinalForm options a b c) =
    Html.Lazy.lazy6 renderHelper attrs maybe options app data (FormInternal a b c)


{-| -}
type FinalForm error parsed data view userMsg
    = FinalForm
        (RenderOptions userMsg)
        (List ( String, FieldDefinition ))
        (Maybe data
         -> FormState
         ->
            { result :
                ( parsed
                , Dict String (List error)
                )
            , isMatchCandidate : Bool
            , view : view
            }
        )
        (data -> List ( String, String ))


{-| -}
toDynamicFetcher :
    String
    ->
        Form
            error
            { combine : Validation.Validation error parsed field constraints
            , view : Context error data -> view
            }
            data
    ->
        FinalForm
            error
            (Validation.Validation error parsed field constraints)
            data
            (Context error data -> view)
            userMsg
toDynamicFetcher name (Form a b c) =
    let
        options : { submitStrategy : SubmitStrategy, method : Method, name : Maybe String, onSubmit : Maybe a }
        options =
            { submitStrategy = FetcherStrategy
            , method = Post
            , name = Just name
            , onSubmit = Nothing
            }

        transformB :
            (Maybe data
             -> FormState
             ->
                { result : Dict String (List error)
                , isMatchCandidate : Bool
                , combineAndView :
                    { combine : Validation error parsed field constraints
                    , view : Context error data -> view
                    }
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
                    , isMatchCandidate : Bool
                    , view : Context error data -> view
                    }
                )
        transformB rawB =
            \maybeData formState ->
                let
                    foo :
                        { result : Dict String (List error)
                        , isMatchCandidate : Bool
                        , combineAndView :
                            { combine : Validation error parsed field constraints
                            , view : Context error data -> view
                            }
                        }
                    foo =
                        rawB maybeData formState
                in
                { result = ( foo.combineAndView.combine, foo.result )
                , view = foo.combineAndView.view
                , isMatchCandidate = foo.isMatchCandidate
                }
    in
    FinalForm options a (transformB b) c


{-| -}
toDynamicTransition :
    String
    ->
        Form
            error
            { combine : Validation.Validation error parsed field constraints
            , view : Context error data -> view
            }
            data
    ->
        FinalForm
            error
            (Validation.Validation error parsed field constraints)
            data
            (Context error data -> view)
            userMsg
toDynamicTransition name (Form a b c) =
    let
        options : { submitStrategy : SubmitStrategy, method : Method, name : Maybe String, onSubmit : Maybe a }
        options =
            { submitStrategy = TransitionStrategy
            , method = Post
            , name = Just name
            , onSubmit = Nothing
            }

        transformB :
            (Maybe data
             -> FormState
             ->
                { result : Dict String (List error)
                , isMatchCandidate : Bool
                , combineAndView :
                    { combine : Validation.Validation error parsed field constraints
                    , view : Context error data -> view
                    }
                }
            )
            ->
                (Maybe data
                 -> FormState
                 ->
                    { result :
                        ( Validation.Validation error parsed field constraints
                        , Dict String (List error)
                        )
                    , isMatchCandidate : Bool
                    , view : Context error data -> view
                    }
                )
        transformB rawB =
            \maybeData formState ->
                let
                    foo :
                        { result : Dict String (List error)
                        , isMatchCandidate : Bool
                        , combineAndView :
                            { combine : Validation.Validation error parsed field constraints
                            , view : Context error data -> view
                            }
                        }
                    foo =
                        rawB maybeData formState
                in
                { result = ( foo.combineAndView.combine, foo.result )
                , view = foo.combineAndView.view
                , isMatchCandidate = foo.isMatchCandidate
                }
    in
    FinalForm options a (transformB b) c


{-| -}
withGetMethod : FinalForm error parsed data view userMsg -> FinalForm error parsed data view userMsg
withGetMethod (FinalForm options a b c) =
    FinalForm { options | method = Get } a b c


{-| -}
withOnSubmit : ({ fields : List ( String, String ) } -> userMsg) -> FinalForm error parsed data view userMsg -> FinalForm error parsed data view userMsg
withOnSubmit onSubmit (FinalForm options a b c) =
    FinalForm { options | onSubmit = Just onSubmit } a b c


{-| -}
renderStyledHtml :
    List (Html.Styled.Attribute (Pages.Msg.Msg msg))
    ->
        Maybe
            { fields : List ( String, String )
            , errors : Dict String (List error)
            }
    -> AppContext app actionData
    -> data
    ->
        FinalForm
            error
            (Validation.Validation error parsed named constraints)
            data
            (Context error data
             -> List (Html.Styled.Html (Pages.Msg.Msg msg))
            )
            msg
    -> Html.Styled.Html (Pages.Msg.Msg msg)
renderStyledHtml attrs maybe app data (FinalForm options a b c) =
    Html.Styled.Lazy.lazy6 renderStyledHelper attrs maybe options app data (FormInternal a b c)


{-| -}
type Response error
    = Response
        { fields : List ( String, String )
        , errors : Dict String (List error)
        }


renderHelper :
    List (Html.Attribute (Pages.Msg.Msg msg))
    ->
        Maybe
            { fields : List ( String, String )
            , errors : Dict String (List error)
            }
    -> RenderOptions msg
    -> AppContext app actionData
    -> data
    -> FormInternal error (Validation.Validation error parsed named constraints) data (Context error data -> List (Html (Pages.Msg.Msg msg)))
    -> Html (Pages.Msg.Msg msg)
renderHelper attrs maybe options formState data form =
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

               -- TODO provide a way to override the action so users can submit to other Routes
               , Attr.action (Path.toAbsolute formState.path)
               , case options.submitStrategy of
                    FetcherStrategy ->
                        Pages.Msg.fetcherOnSubmit options.onSubmit formId (\_ -> isValid)

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
    -> RenderOptions msg
    -> AppContext app actionData
    -> data
    -> FormInternal error (Validation.Validation error parsed named constraints) data (Context error data -> List (Html.Styled.Html (Pages.Msg.Msg msg)))
    -> Html.Styled.Html (Pages.Msg.Msg msg)
renderStyledHelper attrs maybe options formState data form =
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
               , StyledAttr.action (Path.toAbsolute formState.path)
               , case options.submitStrategy of
                    FetcherStrategy ->
                        StyledAttr.fromUnstyled <|
                            Pages.Msg.fetcherOnSubmit options.onSubmit formId (\_ -> isValid)

                    TransitionStrategy ->
                        StyledAttr.fromUnstyled <|
                            Pages.Msg.submitIfValid formId (\_ -> isValid)
               ]
            ++ attrs
        )
        (hiddenInputs ++ children)


helperValues :
    (List (Html.Attribute (Pages.Msg.Msg msg)) -> view)
    ->
        Maybe
            { fields : List ( String, String )
            , errors : Dict String (List error)
            }
    -> RenderOptions msg
    -> AppContext app actionData
    -> data
    ---> Form error parsed data view
    -> FormInternal error (Validation.Validation error parsed named constraints) data (Context error data -> List view)
    -> { formId : String, hiddenInputs : List view, children : List view, isValid : Bool }
helperValues toHiddenInput maybe options formState data (FormInternal fieldDefinitions parser toInitialValues) =
    let
        formId : String
        formId =
            options.name |> Maybe.withDefault ""

        initialValues : Dict String Form.FieldState
        initialValues =
            toInitialValues data
                |> List.map (Tuple.mapSecond (\value -> { value = value, status = FieldStatus.NotVisited }))
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
                                        |> List.map (Tuple.mapSecond (\value -> { value = value, status = FieldStatus.NotVisited }))
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
            { result : ( Validation.Validation error parsed named constraints, Dict String (List error) )
            , isMatchCandidate : Bool
            , view : Context error data -> List view
            }
        parsed =
            parser (Just data) thisFormState

        withoutServerErrors : Validation.Validation error parsed named constraints
        withoutServerErrors =
            parsed |> mergeResults

        withServerErrors : Validation.Validation error parsed named constraints
        withServerErrors =
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
                                        |> List.map (Tuple.mapSecond (\value -> { value = value, status = FieldStatus.NotVisited }))
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
                withServerErrors
                    |> unwrapValidation
                    |> Tuple.second
                    |> Errors
            , isTransitioning =
                -- TODO instead of isTransitioning : Bool, it would be useful to get a custom type with the exact state
                (formState.fetchers |> Dict.member formId)
                    || (case formState.transition of
                            Just (Submitting formData) ->
                                formData.id == Just formId

                            Just (LoadAfterSubmit submitData _ _) ->
                                submitData.id == Just formId

                            Just (Loading _ _) ->
                                False

                            Nothing ->
                                False
                       )
            , submitAttempted = thisFormState.submitAttempted
            , data = data
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
            case withoutServerErrors of
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
type alias DoneForm error parsed data view =
    Form
        error
        { combine : Combined error parsed
        , view : Context error data -> view
        }
        data


{-| -}
type alias HtmlForm error parsed input msg =
    Form
        error
        { combine : Combined error parsed
        , view : Context error input -> List (Html (Pages.Msg.Msg msg))
        }
        input


{-| -}
type ServerForms error parsed
    = ServerForms
        (List
            (Form
                error
                (Combined error parsed)
                Never
            )
        )


{-| -}
initCombined :
    (parsed -> combined)
    ->
        Form
            error
            { combineAndView
                | combine : Validation.Validation error parsed kind constraints
            }
            input
    -> ServerForms error combined
initCombined mapFn (Form _ parseFn _) =
    ServerForms
        [ Form
            []
            (\_ formState ->
                let
                    foo :
                        { result : Dict String (List error)
                        , isMatchCandidate : Bool
                        , combineAndView : { combineAndView | combine : Validation.Validation error parsed kind constraints }
                        }
                    foo =
                        parseFn Nothing formState
                in
                { result = foo.result
                , combineAndView = foo.combineAndView.combine |> Validation.mapWithNever mapFn
                , isMatchCandidate = foo.isMatchCandidate
                }
            )
            (\_ -> [])
        ]


{-| -}
combine :
    (parsed -> combined)
    ->
        Form
            error
            { combineAndView
                | combine : Validation.Validation error parsed kind constraints
            }
            input
    -> ServerForms error combined
    -> ServerForms error combined
combine mapFn (Form _ parseFn _) (ServerForms serverForms) =
    ServerForms
        (serverForms
            ++ [ Form []
                    (\_ formState ->
                        let
                            foo :
                                { result : Dict String (List error)
                                , isMatchCandidate : Bool
                                , combineAndView : { combineAndView | combine : Validation.Validation error parsed kind constraints }
                                }
                            foo =
                                parseFn Nothing formState
                        in
                        { result = foo.result
                        , combineAndView = foo.combineAndView.combine |> Validation.mapWithNever mapFn
                        , isMatchCandidate = foo.isMatchCandidate
                        }
                    )
                    (\_ -> [])
               ]
        )


{-| -}
initCombinedServer :
    (parsed -> combined)
    ->
        Form
            error
            { combineAndView
                | combine : Combined error (BackendTask backendTaskError (Validation.Validation error parsed kind constraints))
            }
            input
    -> ServerForms error (BackendTask backendTaskError (Validation.Validation error combined kind constraints))
initCombinedServer mapFn serverForms =
    initCombined (BackendTask.map (Validation.map mapFn)) serverForms


{-| -}
combineServer :
    (parsed -> combined)
    ->
        Form
            error
            { combineAndView
                | combine :
                    Combined error (BackendTask backendTaskError (Validation.Validation error parsed kind constraints))
            }
            input
    -> ServerForms error (BackendTask backendTaskError (Validation.Validation error combined kind constraints))
    -> ServerForms error (BackendTask backendTaskError (Validation.Validation error combined kind constraints))
combineServer mapFn a b =
    combine (BackendTask.map (Validation.map mapFn)) a b


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
            , isMatchCandidate : Bool
            , view : view
            }
        )
        (data -> List ( String, String ))


{-| -}
type Form error combineAndView input
    = Form
        (List ( String, FieldDefinition ))
        (Maybe input
         -> FormState
         ->
            { result : Dict String (List error)
            , isMatchCandidate : Bool
            , combineAndView : combineAndView
            }
        )
        (input -> List ( String, String ))


type alias RenderOptions userMsg =
    { submitStrategy : SubmitStrategy
    , method : Method
    , name : Maybe String
    , onSubmit : Maybe ({ fields : List ( String, String ) } -> userMsg)
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
