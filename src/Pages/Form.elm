module Pages.Form exposing
    ( renderHtml, renderStyledHtml
    , FormWithServerValidations, Handler
    , Options
    , withConcurrent
    )

{-|

@docs renderHtml, renderStyledHtml

@docs FormWithServerValidations, Handler

@docs Options


## Form Submission Strategies

When you render with [`Pages.Form.renderHtml`](#renderHtml) or [`Pages.Form.renderStyledHtml`](#renderStyledHtml),
`elm-pages` progressively enhances form submissions to manage the requests through Elm (instead of as a vanilla HTML form submission, which performs a full page reload).

By default, `elm-pages` Forms will use the same mental model as the browser's default form submission behavior. That is, the form submission state will be tied to the page's navigation state.
If you click a link while a form is submitting, the form submission will be cancelled and the page will navigate to the new page. Conceptually, you can think of this as being tied to the navigation state.
A form submission is part of the page's navigation state, and so is a page navigation. So if you have a page with an edit form, a delete form (no inputs but only a delete button), and a link to a new page,
you can interact with any of these and it will cancel the previous interactions.

You can access this state through `app.navigation` in your `Route` module, which is a value of type [`Pages.Navigation`](Pages-Navigation).

This default form submission strategy is a good fit for more linear actions. This is more traditional server submission behavior that you might be familiar with from Rails or other server frameworks without JavaScript enhancement.

@docs withConcurrent

-}

import BackendTask exposing (BackendTask)
import Dict exposing (Dict)
import FatalError exposing (FatalError)
import Form
import Form.Handler
import Form.Validation exposing (Validation)
import Html
import Html.Styled
import Pages.ConcurrentSubmission
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


{-| Instead of using the default submission strategy (tied to the page's navigation state), you can use `withConcurrent`.
`withConcurrent` allows multiple form submissions to be in flight at the same time. It is useful for more dynamic applications. A good rule of thumb
is if you could have multiple pending spinners on the page at the same time, you should use `withConcurrent`. For example, if you have a page with a list of items,
say a Twitter clone. If you click the like button on a Tweet, it won't result in a page navigation. You can click the like button on multiple Tweets at the same time
and they will all submit independently.

In the case of Twitter, there isn't an indication of a loading spinner on the like button because it is expected that it will succeed. This is an example of a User Experience (UX) pattern
called Optimistic UI. Since it is very likely that liking a Tweet will be successful, the UI will update the UI as if it has immediately succeeded even though the request is still in flight.
If the request fails, the UI will be updated to reflect the failure with an animation to show that something went wrong.

The `withConcurrent` is a good fit for either of these UX patterns (Optimistic UI or Pending UI, i.e. showing a loading spinner). You can derive either of these
visual states from the `app.concurrentSubmissions` field in your `Route` module.

-}
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
            , concurrentSubmissions : Dict String (Pages.ConcurrentSubmission.ConcurrentSubmission (Maybe action))
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
                            Pages.ConcurrentSubmission.Complete _ ->
                                False

                            Pages.ConcurrentSubmission.Submitting ->
                                True

                            Pages.ConcurrentSubmission.Reloading _ ->
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
            , concurrentSubmissions : Dict String (Pages.ConcurrentSubmission.ConcurrentSubmission (Maybe action))
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
                            Pages.ConcurrentSubmission.Complete _ ->
                                False

                            Pages.ConcurrentSubmission.Submitting ->
                                True

                            Pages.ConcurrentSubmission.Reloading _ ->
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
