---
title: Native semantics fixture
---

[TOC]

# Reader semantics

This document checks native Android rendering and navigation.

## Footnote navigation

This sentence links to a note[^1] and to [the reference][source].

[^1]: The footnote body must render once and link back to its reference.

[source]: https://example.invalid/reference

## Multiline math

The display equation remains one block:

$$
E = mc^2
$$

This paragraph follows the equation.
