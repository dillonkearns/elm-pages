module AllMetadata exposing (..)

import Template.BlogIndex
import Template.BlogPost
import Template.Page
import Template.Showcase


type Metadata
    = MetadataBlogPost Template.BlogPost.Metadata
    | MetadataShowcase Template.Showcase.Metadata
    | MetadataPage Template.Page.Metadata
    | MetadataBlogIndex Template.BlogIndex.Metadata
