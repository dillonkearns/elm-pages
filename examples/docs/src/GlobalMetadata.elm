module GlobalMetadata exposing (..)

import TemplateMetadata


type Metadata
    = MetadataBlogPost TemplateMetadata.BlogPost
    | MetadataShowcase TemplateMetadata.Showcase
    | MetadataPage TemplateMetadata.Page
    | MetadataBlogIndex TemplateMetadata.BlogIndex
    | MetadataDocumentation TemplateMetadata.Documentation
