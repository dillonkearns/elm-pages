module TemplateDocument exposing (..)

import Browser
import Element exposing (Element)
import GlobalMetadata
import Html exposing (Html)
import MarkdownRenderer
import Pages
import Template exposing (Template)


type alias View msg =
    { title : String, body : Element msg }


type alias RenderedBody msg =
    ( MarkdownRenderer.TableOfContents, List (Element msg) )


type alias TemplateDocument templateMetadata templateStaticData templateModel templateMsg =
    Template Pages.PathKey templateMetadata (RenderedBody Never) templateStaticData templateModel (View Never) templateMsg GlobalMetadata.Metadata
