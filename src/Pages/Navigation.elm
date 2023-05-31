module Pages.Navigation exposing (Navigation(..), LoadingState(..))

{-| `elm-pages` maintains a single `Maybe Navigation` state which is accessible from your `Route` modules through `app.navigation`.

You can use it to show a loading indicator while a page is loading:

    import Pages.Navigation as Navigation

    pageLoadingIndicator app =
        case app.navigation of
            Just (Navigation.Loading path _) ->
                Spinner.view

            Nothing ->
                emptyView

    emptyView : Html msg
    emptyView =
        Html.text ""

You can also use it to derive Pending UI or Optimistic UI from a pending form submission:

    import Form
    import Form.Handler
    import Pages.Navigation as Navigation

    view app =
        let
            optimisticProduct : Maybe Product
            optimisticProduct =
                case app.navigation of
                    Just (Navigation.Submitting formData) ->
                        formHandler
                            |> Form.Handler.run formData
                            |> Form.toResult
                            |> Result.toMaybe

                    Just (Navigation.LoadAfterSubmit formData path _) ->
                        formHandler
                            |> Form.Handler.run formData
                            |> Form.toResult
                            |> Result.toMaybe

                    Nothing ->
                        Nothing
        in
        -- our `productsView` function could show a loading spinner (Pending UI),
        -- or it could assume the product will be created successfully (Optimistic UI) and
        -- display it as a regular product in the list
        productsView optimisticProduct app.data.products

    allForms : Form.Handler.Handler String Product
    allForms =
        Form.Handler.init identity productForm

    editItemForm : Form.HtmlForm String Product input msg
    editItemForm =
        Debug.todo "Form definition here"

@docs Navigation, LoadingState

-}

import Pages.FormData exposing (FormData)
import UrlPath exposing (UrlPath)


{-| Represents the global page navigation state of the app.

  - `Loading` - navigating to a page, for example from a link click, or from a programmatic navigation with `Browser.Navigation.pushUrl`.
  - `Submitting` - submitting a form using the default submission strategy (note that Forms rendered with the [`Pages.Form.withConcurrent`](Pages-Form#withConcurrent) Option have their state managed in `app.concurrentSubmissions` instead of `app.navigation`).
  - `LoadAfterSubmit` - the state immediately after `Submitting` - allows you to continue using the `FormData` from a submission while a data reload or redirect is occurring.

-}
type Navigation
    = Submitting FormData
    | LoadAfterSubmit FormData UrlPath LoadingState
    | Loading UrlPath LoadingState


{-| -}
type LoadingState
    = Redirecting
    | Load
    | ActionRedirect
