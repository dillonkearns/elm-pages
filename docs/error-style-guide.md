# Error Template and Philosophy

This document is inspired by the Elm compiler's famously helpful (and friendly!) error messages.

`elm-pages` strives to be as delightful to use as Elm, and to feel like a familiar experience to Elm users,
both in terms of the concepts, and the feel of the development cycle and feedback style.

## Error Message Resources & Inspiration

- https://elm-lang.org/news/compiler-errors-for-humans
- https://elm-lang.org/news/the-syntax-cliff
- Gatsby is working on redesignging their CLI error messages, and has listed out a lot of references of
  UX ideas for CLIs, and descriptions of CLI UX from common tools: https://www.gatsbyjs.org/blog/2019-05-22-cli-error-redesign

## Error Message Structure

Concise context should be presented before the code snippet (or equivalent).
Further guidance and hints should be provided below that (in many cases, people won't need to scroll down to see that).

The helpful error message often has these 3 things:

**Context**

How can we help the user find where/why something went wrong?

**Suggestion**

How can we guide the user to quickly and easily fix the problem or accomplish the task they're trying to accomplish?

**Educational Material**

How can we present information and resources that help them understand concepts that they might be missing that they need to solve their issue or accomplish their goal?

### Example Breakdown

**CONTEXT**

```
I was trying to parse the file `content/blog/my-post.txt`

But I didn't find a `Pages.DocumentHandler` for `.txt` files in your `Pages.Platform.application` config.

You have document parsers for the following extensions:
`.md`, `.emu`, `.json`
```

**SUGGESTION**

```
So you could either:
1) Create your new file with one of those extensions, like `content/blog/my-post.md`
2) Move the file `content/blog/my-post.txt` outside of the `content` folder, or delete it
3) Add a `Pages.DocumentHandler` for `.txt` files, something like

    Pages.Document.parser
        { extension = "txt"
        , metadata = Decode.succeed ()
        , body = \_ -> Ok ()
        }
```

**EDUCATIONAL MATERIAL**

```
You can learn more about how elm-pages deals with parsing different document types,
and some techniques and best practices for managing your content files and metadata types
at elm-pages.com/docs/document-handlers
```

## Details About The 3 Elements of Error Structure

Let's break these down further with some examples and key ideas for each.

### Context

How can we help the user find where/why something went wrong?

Examples of useful context:

- "I was parsing the frontmatter for the file at `./content/blog/my-post.md`"

## Suggestion

How can we guide the user to quickly and easily fix the problem or accomplish the task they're trying to accomplish?

Key concepts

- Make it as actionable as possible
  - Code snippets should compile when copy-pasted if possible
  - List out possible options to make it clear when there are alternatives

Examples:

- See "Suggestion" section in [Example Breakdown](#example-breakdown)

## Educational Material

How can we present information and resources that help them understand concepts that they might be missing that they need to solve their issue or accomplish their goal?

Key ideas

- Often the user is trying to accomplish something different than the error message context would imply. For
  example, if they are running into an error message about parsing frontmatter, they may
  just need some help understanding the concept of what frontmatter is, what the valid syntax is,
  or how it differs from tools with special frontmatter directives (like Jekyll). So the context is
  that their decoder is failing... but that context may not point them in the direction they need at all.
  This is often the purpose that educational material serves.

Examples:

- "I was trying to parse the frontmatter for page ..., but there was no frontmatter. Frontmatter is metadata about a page, for example a page might have a title or a published date or a list of tags. See link to learn more about frontmatter and best practices for using it with `elm-pages`"
- Many static site frameworks have custom frontmatter directives. In `elm-pages`, you define a JSON decoder, and then decide what to do with that parsed data in your `view` function. Learn more at elm-pages.com/docs/elm-pages-architecture

## Error message design process

Error messages are part of the UX of `elm-pages`. People will be looking at these frequently when they work with `elm-pages`, so
it's a very important part of it. Always consider the user's goal (from the user's perspective) when thinking about error messages.

It's worth putting care into error messages, just as you would any other aspect of user experience.
And as with user experience design, I think that making low-fi error message "mock ups" could be an
extermely helpful exercise. I envision having Github issues with **current error message**, and
**suggested error message mock-up** sections, and having community discussions where we can tweak mock-ups
and propose changes, or explore them through the lens of this Error Style Guide.

## Where/when to present errors

Let the user know as soon as possible. For example, if you can show them an error in their browser
as they're editing the frontmatter for a document, do that.

Use what's avaialble in the context where they're viewing the error to make it as useful as possible.

If you're in a terminal, use nice syntax highlighting (and even terminal URL style contentions to make them clickable)

If you're in the browser, use anchor tags to link as much as possible, and nice HTML formatting to make structure more clear and easier to navigate.

You can even make error messages searchable, filterable, sortable, etc.
