module Main exposing (main)

import Browser
import Browser.Navigation as Nav
import Html exposing (..)
import Html.Attributes exposing (..)
import Markdown.Parser as Markdown
import Url


main : Program () Model Msg
main =
    Browser.document
        { init = init
        , view = view
        , update = update
        , subscriptions = \_ -> Sub.none
        }


type alias Model =
    ()


init : () -> ( Model, Cmd Msg )
init flags =
    ( (), Cmd.none )


type Msg
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    ( model, Cmd.none )


view : Model -> Browser.Document Msg
view model =
    { title = "elm-markdown-parser"
    , body = [ mainView ]
    }


markdown =
    """# Hello 👋

Welcome to this document!

## Features

Let me tell you why I built this...

<Red>
# Is this red? 😺

It seems to be! 👌
<Blue>
This should be blue in red!
</Blue>
</Red>

This should be plain markdown text.

<Blue>
# Is this blue? 😺

It seems to be! 👌
</Blue>
"""


mainView : Html msg
mainView =
    markdown
        |> Markdown.render
            { heading = \level content -> Html.h1 [] [ Html.text content ]
            , raw =
                \styledList ->
                    styledList
                        |> List.map
                            (\{ string, style } ->
                                -- TODO use style here
                                Html.text string
                            )
                        |> Html.p []
            , todo = Html.text "TODO"
            , htmlDecoder =
                Markdown.htmlOneOf
                    [ Markdown.htmlTag "Red"
                        (\children ->
                            Html.div [ style "background-color" "red" ]
                                children
                        )
                    , Markdown.htmlTag "Blue"
                        (\children ->
                            Html.div [ style "background-color" "blue" ]
                                children
                        )
                    ]
            }
        |> Result.map (Html.div [])
        |> (\result ->
                case result of
                    Ok content ->
                        content

                    Err error ->
                        error
                            |> Debug.toString
                            |> Html.text
           )
