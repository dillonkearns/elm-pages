module GlobalMetadata exposing (..)

import Template.Metadata


type Metadata
    = MetadataBlogPost Template.Metadata.BlogPost
    | MetadataShowcase Template.Metadata.Showcase
    | MetadataPage Template.Metadata.Page
    | MetadataBlogIndex Template.Metadata.BlogIndex
