module Pages.Form exposing (Options, options, renderHtml, renderStyledHtml, withInput, withOnSubmit, withParallel, withServerResponse)

import Dict exposing (Dict)
import Form
import Form.Validation exposing (Validation)
import Html
import Html.Styled
import Pages.Internal.Msg
import Pages.Transition
import PagesMsg exposing (PagesMsg)


type alias Options error parsed input msg =
    -- TODO have a way to override path?
    --path : Path
    { id : String
    , input : input
    , parallel : Bool
    , onSubmit : Maybe (Form.Validated error parsed -> msg)
    , serverResponse : Maybe (Form.ServerResponse error)
    }


options : String -> Options error parsed () msg
options id =
    { id = id
    , input = ()
    , parallel = False
    , onSubmit = Nothing
    , serverResponse = Nothing
    }


withParallel : Options error parsed input msg -> Options error parsed input msg
withParallel options_ =
    { options_ | parallel = True }


withServerResponse : Maybe (Form.ServerResponse error) -> Options error parsed input msg -> Options error parsed input msg
withServerResponse serverResponse options_ =
    { options_ | serverResponse = serverResponse }


withInput : input -> Options error parsed () msg -> Options error parsed input msg
withInput input options_ =
    { id = options_.id
    , input = input
    , parallel = options_.parallel
    , onSubmit = options_.onSubmit
    , serverResponse = options_.serverResponse
    }


withOnSubmit : (Form.Validated error parsed -> msg) -> Options error parsed input previousMsg -> Options error parsed input msg
withOnSubmit onSubmit options_ =
    { id = options_.id
    , input = options_.input
    , parallel = options_.parallel
    , onSubmit = Just onSubmit
    , serverResponse = options_.serverResponse
    }


renderHtml :
    List (Html.Attribute (PagesMsg userMsg))
    -> Options error parsed input userMsg
    ->
        { --path : Path
          --, url : Maybe PageUrl
          --, action : Maybe action
          app
            | pageFormState : Form.Model
            , transition : Maybe Pages.Transition.Transition
            , fetchers : Dict String (Pages.Transition.FetcherState (Maybe action))
        }
    -> Form.Form error { combine : Validation error parsed named constraints, view : Form.Context error input -> List (Html.Html (PagesMsg userMsg)) } parsed input (PagesMsg userMsg)
    -> Html.Html (PagesMsg userMsg)
renderHtml attrs options_ app form_ =
    form_
        |> Form.renderHtml
            options_.id
            attrs
            { state = app.pageFormState
            , serverResponse = options_.serverResponse
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
            , onSubmit =
                Just
                    (\{ fields, action, parsed } ->
                        case parsed of
                            Form.Valid _ ->
                                Pages.Internal.Msg.Submit
                                    { useFetcher = options_.parallel
                                    , action = action
                                    , fields = fields
                                    , msg = options_.onSubmit |> Maybe.map (\onSubmit -> onSubmit parsed)
                                    , id = options_.id
                                    , valid = True
                                    }

                            Form.Invalid _ _ ->
                                Pages.Internal.Msg.Submit
                                    { useFetcher = options_.parallel
                                    , action = action
                                    , fields = fields
                                    , msg = options_.onSubmit |> Maybe.map (\onSubmit -> onSubmit parsed)
                                    , id = options_.id
                                    , valid = False
                                    }
                    )
            }
            options_.input


renderStyledHtml :
    List (Html.Styled.Attribute (PagesMsg userMsg))
    -> Options error parsed input userMsg
    ->
        { --path : Path
          --, url : Maybe PageUrl
          --, action : Maybe action
          app
            | pageFormState : Form.Model
            , transition : Maybe Pages.Transition.Transition
            , fetchers : Dict String (Pages.Transition.FetcherState (Maybe action))
        }
    -> Form.Form error { combine : Validation error parsed named constraints, view : Form.Context error input -> List (Html.Styled.Html (PagesMsg userMsg)) } parsed input (PagesMsg userMsg)
    -> Html.Styled.Html (PagesMsg userMsg)
renderStyledHtml attrs options_ app form_ =
    form_
        |> Form.renderStyledHtml
            options_.id
            attrs
            { state = app.pageFormState
            , serverResponse = options_.serverResponse
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
            , onSubmit =
                Just
                    (\{ fields, action, parsed } ->
                        case parsed of
                            Form.Valid _ ->
                                Pages.Internal.Msg.Submit
                                    { useFetcher = options_.parallel
                                    , fields = fields
                                    , msg = options_.onSubmit |> Maybe.map (\onSubmit -> onSubmit parsed)
                                    , id = options_.id
                                    , valid = True
                                    , action = action
                                    }

                            Form.Invalid _ _ ->
                                Pages.Internal.Msg.Submit
                                    { useFetcher = options_.parallel
                                    , fields = fields
                                    , msg = options_.onSubmit |> Maybe.map (\onSubmit -> onSubmit parsed)
                                    , id = options_.id
                                    , valid = False
                                    , action = action
                                    }
                    )
            }
            options_.input
