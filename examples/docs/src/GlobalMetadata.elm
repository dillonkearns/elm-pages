module TemplateType exposing (..)

import TemplateMetadata


type Metadata
    = BlogPost TemplateMetadata.BlogPost
    | Showcase TemplateMetadata.Showcase
    | Page TemplateMetadata.Page
    | BlogIndex TemplateMetadata.BlogIndex
    | Documentation TemplateMetadata.Documentation
