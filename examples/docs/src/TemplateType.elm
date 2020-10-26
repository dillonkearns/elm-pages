module TemplateType exposing (TemplateType(..))

import TemplateMetadata


type TemplateType
    = BlogPost TemplateMetadata.BlogPost
    | Showcase TemplateMetadata.Showcase
    | Page TemplateMetadata.Page
    | BlogIndex TemplateMetadata.BlogIndex
    | Documentation TemplateMetadata.Documentation
