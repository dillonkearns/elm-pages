module Pages.Form exposing
    ( renderHtml, renderStyledHtml
    , FormWithServerValidations, Handler
    , Options, withConcurrent
    )

{-|

@docs renderHtml, renderStyledHtml

@docs FormWithServerValidations, Handler

@docs Options, withConcurrent

-}

import BackendTask exposing (BackendTask)
import Dict exposing (Dict)
import FatalError exposing (FatalError)
import Form
import Form.Handler
import Form.Validation exposing (Validation)
import Html
import Html.Styled
import Pages.Internal.Msg
import Pages.Navigation
import PagesMsg exposing (PagesMsg)


{-| -}
type alias FormWithServerValidations error combined input view =
    Form.Form
        error
        { combine :
            Validation
                error
                (BackendTask FatalError (Validation error combined Never Never))
                Never
                Never
        , view : Form.Context error input -> view
        }
        (BackendTask FatalError (Validation error combined Never Never))
        input


{-| -}
type alias Handler error combined =
    Form.Handler.Handler error (BackendTask FatalError (Validation error combined Never Never))


{-| -}
type alias Options error parsed input msg =
    Form.Options error parsed input msg { concurrent : Bool }


withConcurrent : Options error parsed input msg -> Options error parsed input msg
withConcurrent options_ =
    { options_ | extras = Just { concurrent = True } }



--init :
--    (parsed -> combined)
--    -> FormWithServerValidations error parsed input view
--    -> Handler error combined
--init mapFn form =
--    Form.Handler.init
--        (\something ->
--            let
--                foo : parsed
--                foo =
--                    something
--
--                goal : BackendTask FatalError (Validation error combined Never Never)
--                goal =
--                    Debug.todo ""
--            in
--            --Form.Validation.map (BackendTask.map (mapFn something))
--            --Debug.todo ""
--            goal
--        )
--        form


{-| -}
renderHtml :
    List (Html.Attribute (PagesMsg userMsg))
    -> Options error parsed input userMsg
    ->
        { --path : Path
          --, url : Maybe PageUrl
          --, action : Maybe action
          app
            | pageFormState : Form.Model
            , navigation : Maybe Pages.Navigation.Navigation
            , concurrentSubmissions : Dict String (Pages.Navigation.FetcherState (Maybe action))
        }
    -> Form.Form error { combine : Validation error parsed named constraints, view : Form.Context error input -> List (Html.Html (PagesMsg userMsg)) } parsed input
    -> Html.Html (PagesMsg userMsg)
renderHtml attrs options_ app form_ =
    let
        concurrent : Bool
        concurrent =
            options_.extras |> Maybe.map .concurrent |> Maybe.withDefault False
    in
    form_
        |> Form.renderHtml
            { state = app.pageFormState
            , submitting =
                (case app.concurrentSubmissions |> Dict.get options_.id of
                    Just { status } ->
                        case status of
                            Pages.Navigation.FetcherComplete _ ->
                                False

                            Pages.Navigation.FetcherSubmitting ->
                                True

                            Pages.Navigation.FetcherReloading _ ->
                                True

                    Nothing ->
                        False
                )
                    || (case app.navigation of
                            Just (Pages.Navigation.Submitting formData) ->
                                formData.id == Just options_.id

                            Just (Pages.Navigation.LoadAfterSubmit submitData _ _) ->
                                submitData.id == Just options_.id

                            Just (Pages.Navigation.Loading _ _) ->
                                False

                            Nothing ->
                                False
                       )
            , toMsg = Pages.Internal.Msg.FormMsg
            }
            { id = options_.id
            , method = options_.method
            , input = options_.input
            , serverResponse = options_.serverResponse
            , action = options_.action
            , onSubmit =
                Just
                    (\submission ->
                        case submission.parsed of
                            Form.Valid _ ->
                                Pages.Internal.Msg.Submit
                                    { useFetcher = concurrent
                                    , action = submission.action
                                    , fields = submission.fields
                                    , method = submission.method
                                    , msg =
                                        options_.onSubmit
                                            |> Maybe.map
                                                (\onSubmit -> onSubmit submission)
                                    , id = options_.id
                                    , valid = True
                                    }

                            Form.Invalid _ _ ->
                                Pages.Internal.Msg.Submit
                                    { useFetcher = concurrent
                                    , action = submission.action
                                    , method = submission.method
                                    , fields = submission.fields
                                    , msg = options_.onSubmit |> Maybe.map (\onSubmit -> onSubmit submission)
                                    , id = options_.id
                                    , valid = False
                                    }
                    )
            , extras = Nothing
            }
            attrs


{-| -}
renderStyledHtml :
    List (Html.Styled.Attribute (PagesMsg userMsg))
    -> Options error parsed input userMsg
    ->
        { --path : Path
          --, url : Maybe PageUrl
          --, action : Maybe action
          app
            | pageFormState : Form.Model
            , navigation : Maybe Pages.Navigation.Navigation
            , concurrentSubmissions : Dict String (Pages.Navigation.FetcherState (Maybe action))
        }
    -> Form.Form error { combine : Validation error parsed named constraints, view : Form.Context error input -> List (Html.Styled.Html (PagesMsg userMsg)) } parsed input
    -> Html.Styled.Html (PagesMsg userMsg)
renderStyledHtml attrs options_ app form_ =
    let
        concurrent : Bool
        concurrent =
            options_.extras |> Maybe.map .concurrent |> Maybe.withDefault False
    in
    form_
        |> Form.renderStyledHtml
            { state = app.pageFormState
            , toMsg = Pages.Internal.Msg.FormMsg
            , submitting =
                (case app.concurrentSubmissions |> Dict.get options_.id of
                    Just { status } ->
                        case status of
                            Pages.Navigation.FetcherComplete _ ->
                                False

                            Pages.Navigation.FetcherSubmitting ->
                                True

                            Pages.Navigation.FetcherReloading _ ->
                                True

                    Nothing ->
                        False
                )
                    || (case app.navigation of
                            Just (Pages.Navigation.Submitting formData) ->
                                formData.id == Just options_.id

                            Just (Pages.Navigation.LoadAfterSubmit submitData _ _) ->
                                submitData.id == Just options_.id

                            Just (Pages.Navigation.Loading _ _) ->
                                False

                            Nothing ->
                                False
                       )
            }
            { id = options_.id
            , method = options_.method
            , input = options_.input
            , serverResponse = options_.serverResponse
            , action = options_.action
            , onSubmit =
                Just
                    (\submission ->
                        case submission.parsed of
                            Form.Valid _ ->
                                Pages.Internal.Msg.Submit
                                    { useFetcher = concurrent
                                    , action = submission.action
                                    , fields = submission.fields
                                    , method = submission.method
                                    , msg =
                                        options_.onSubmit
                                            |> Maybe.map
                                                (\onSubmit -> onSubmit submission)
                                    , id = options_.id
                                    , valid = True
                                    }

                            Form.Invalid _ _ ->
                                Pages.Internal.Msg.Submit
                                    { useFetcher = concurrent
                                    , action = submission.action
                                    , fields = submission.fields
                                    , method = submission.method
                                    , msg = options_.onSubmit |> Maybe.map (\onSubmit -> onSubmit submission)
                                    , id = options_.id
                                    , valid = False
                                    }
                    )
            , extras = Nothing
            }
            attrs
