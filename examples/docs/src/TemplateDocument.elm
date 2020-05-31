module TemplateDocument exposing (..)

import Element exposing (Element)
import GlobalMetadata
import MarkdownRenderer
import Pages
import Template exposing (Template)


type alias View msg =
    { title : String, body : Element msg }


type alias RenderedMarkdown msg =
    ( MarkdownRenderer.TableOfContents, List (Element msg) )


type alias TemplateDocument templateMetadata templateStaticData templateModel templateMsg =
    Template Pages.PathKey templateMetadata (RenderedMarkdown Never) templateStaticData templateModel (View Never) templateMsg GlobalMetadata.Metadata
