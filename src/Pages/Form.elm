module Pages.Form exposing (Strategy(..), renderHtml, renderStyledHtml)

import Dict exposing (Dict)
import Form
import Form.Validation exposing (Validation)
import Html
import Html.Styled
import Pages.Internal.Msg
import Pages.Transition
import PagesMsg exposing (PagesMsg)


type Strategy
    = Parallel
    | Serial


renderHtml :
    List (Html.Attribute (PagesMsg userMsg))
    -> Strategy
    -> Form.Options error parsed input userMsg
    ->
        { --path : Path
          --, url : Maybe PageUrl
          --, action : Maybe action
          app
            | pageFormState : Form.Model
            , transition : Maybe Pages.Transition.Transition
            , fetchers : Dict String (Pages.Transition.FetcherState (Maybe action))
        }
    -> Form.Form error { combine : Validation error parsed named constraints, view : Form.Context error input -> List (Html.Html (PagesMsg userMsg)) } parsed input
    -> Html.Html (PagesMsg userMsg)
renderHtml attrs strategy options_ app form_ =
    form_
        |> Form.renderHtml
            { state = app.pageFormState
            , submitting =
                (case app.fetchers |> Dict.get options_.id of
                    Just { status } ->
                        case status of
                            Pages.Transition.FetcherComplete _ ->
                                False

                            Pages.Transition.FetcherSubmitting ->
                                True

                            Pages.Transition.FetcherReloading _ ->
                                True

                    Nothing ->
                        False
                )
                    || (case app.transition of
                            Just (Pages.Transition.Submitting formData) ->
                                formData.id == Just options_.id

                            Just (Pages.Transition.LoadAfterSubmit submitData _ _) ->
                                submitData.id == Just options_.id

                            Just (Pages.Transition.Loading _ _) ->
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
            , onSubmit =
                Just
                    (\submission ->
                        case submission.parsed of
                            Form.Valid _ ->
                                Pages.Internal.Msg.Submit
                                    { useFetcher = strategy == Parallel
                                    , action = submission.action
                                    , fields = submission.fields
                                    , msg =
                                        options_.onSubmit
                                            |> Maybe.map
                                                (\onSubmit -> onSubmit submission)
                                    , id = options_.id
                                    , valid = True
                                    }

                            Form.Invalid _ _ ->
                                Pages.Internal.Msg.Submit
                                    { useFetcher = strategy == Parallel
                                    , action = submission.action
                                    , fields = submission.fields
                                    , msg = options_.onSubmit |> Maybe.map (\onSubmit -> onSubmit submission)
                                    , id = options_.id
                                    , valid = False
                                    }
                    )
            }
            attrs


renderStyledHtml :
    List (Html.Styled.Attribute (PagesMsg userMsg))
    -> Strategy
    -> Form.Options error parsed input userMsg
    ->
        { --path : Path
          --, url : Maybe PageUrl
          --, action : Maybe action
          app
            | pageFormState : Form.Model
            , transition : Maybe Pages.Transition.Transition
            , fetchers : Dict String (Pages.Transition.FetcherState (Maybe action))
        }
    -> Form.Form error { combine : Validation error parsed named constraints, view : Form.Context error input -> List (Html.Styled.Html (PagesMsg userMsg)) } parsed input
    -> Html.Styled.Html (PagesMsg userMsg)
renderStyledHtml attrs strategy options_ app form_ =
    form_
        |> Form.renderStyledHtml
            { state = app.pageFormState
            , toMsg = Pages.Internal.Msg.FormMsg
            , submitting =
                (case app.fetchers |> Dict.get options_.id of
                    Just { status } ->
                        case status of
                            Pages.Transition.FetcherComplete _ ->
                                False

                            Pages.Transition.FetcherSubmitting ->
                                True

                            Pages.Transition.FetcherReloading _ ->
                                True

                    Nothing ->
                        False
                )
                    || (case app.transition of
                            Just (Pages.Transition.Submitting formData) ->
                                formData.id == Just options_.id

                            Just (Pages.Transition.LoadAfterSubmit submitData _ _) ->
                                submitData.id == Just options_.id

                            Just (Pages.Transition.Loading _ _) ->
                                False

                            Nothing ->
                                False
                       )
            }
            { id = options_.id
            , method = options_.method
            , input = options_.input
            , serverResponse = options_.serverResponse
            , onSubmit =
                Just
                    (\submission ->
                        case submission.parsed of
                            Form.Valid _ ->
                                Pages.Internal.Msg.Submit
                                    { useFetcher = strategy == Parallel
                                    , action = submission.action
                                    , fields = submission.fields
                                    , msg =
                                        options_.onSubmit
                                            |> Maybe.map
                                                (\onSubmit -> onSubmit submission)
                                    , id = options_.id
                                    , valid = True
                                    }

                            Form.Invalid _ _ ->
                                Pages.Internal.Msg.Submit
                                    { useFetcher = strategy == Parallel
                                    , action = submission.action
                                    , fields = submission.fields
                                    , msg = options_.onSubmit |> Maybe.map (\onSubmit -> onSubmit submission)
                                    , id = options_.id
                                    , valid = False
                                    }
                    )
            }
            attrs
