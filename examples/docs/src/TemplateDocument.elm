module TemplateDocument exposing (..)

import Browser
import Element exposing (Element)
import Global
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
    Template Pages.PathKey templateMetadata Global.RenderedBody templateStaticData templateModel (View templateMsg) templateMsg GlobalMetadata.Metadata
