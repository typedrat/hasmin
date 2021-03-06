# Changelog
This project adheres to [PVP](https://pvp.haskell.org).

## 1.0.2
### Added
* `caret-color` and `font-display` to the property traits table, enabling their minification.
* `border-radius` minification.
* Parsing and minification of `<basic-shape>`.

### Improved
* Position minification

## 1.0.1

### Added

* Removing `all` and `all and` in media query lists, since `all`
  is assumed when not present. In other words, the following
  rules are equivalent:
  ```css
  @media all {/*..*/}
  @media {/*..*/}
  ```
  and so are these:
  ```css
  @media all and (min-width: 500px) {/*..*/}
  @media (min-width: 500px) {/*..*/}
  ```
  Note that this applies to media query lists in at-import rules too.

* Replacing the `url()` notation for a \<string> when used in the `@import`
  rule.

* Four pseudoelement minifications:

  1. `:nth-of-type(1)` --> `:first-of-type`.
  2. `:nth-last-of-type(1)` --> `:last-of-type`.
  3. `:nth-child(1)` --> `:first-child`.
  4. `:nth-last-child(1)` --> `:last-child`.

* `[class~=x]` to `.x` minification.

### Improved
* \<position> parser, making hasmin around four times faster on stylesheets with
  many \<position> values.

### Fixed
* Length's Eq instance, which would equate lengths with the same numerical
  value when one had an absolute unit, and the other relative, e.g. 1in and 1em.
* Escaped character conversion: converting characters would crash the program
  when:

    1. The escaped character had more than 6 hexadecimal digits (6 is the specs
       maximum); E.g. `\aaaaaaa`.
    2. The escaped character's numerical representation was out of the unicode
       range.

  This is no longer the case.

## 1.0

### Added
* `border-color-*`, `border-width-*` and `border-style-*` longhands are now
   replaced by their shorthand, when the four corresponding longhands are
   present in a rule.
* Style rules merging: merges pairs of rules that either have all the
  same selectors, or all the same declarations. For it to be safe, it only does
  so whenever two conditions don't meet:
    1. There is a rule in between with the same specificity
    2. This rule has a declaration that "clashes" (interferes) with one of the
       declarations of the rules to be merged.

  By default it is enabled, but it can be disabled with `--no-rule-merging` (or
  using a `Config` with `MergeRulesOn`).

### Changed
* Replaced `--no-property-sorting` for `--sort-properties`. Now Hasmin doesn't
  sort properties by default; sorting declarations became opt-in rather than
  opt-out. This is because:
    1. Whether lexicographical sorting of properties aids compression varies a
       lot from stylesheet to stylesheet, for some files it helps, for others it
       hurts.
    2. The current implementation doesn't take into account all the possible
       interactions between properties, making it unsafe.

### Fixed
* Fixed non-exhaustive pattern bug introduced in 0.3.3
* Fixed parser choking with rules that contained a semicolon but no
  declarations, e.g. `div { ; }`.

## 0.3.3 [YANKED]
This version introduced a non-exhaustive pattern bug. Don't use it.

### Added
Added a simple merging of adjacent media queries (`@media` rules), e.g.:
```css
@media all and (min-width: 24rem) {
  a { font-size: 1.2rem; }
}
@media all and (min-width: 24rem) {
  b { padding-left: .25rem; padding-right: .25rem; }
}
```
Gets merged into into:
```css
@media all and (min-width: 24rem) {
  a { font-size: 1.2rem; }
  b { padding-left: .25rem; padding-right: .25rem; }
}
```

## 0.3.2.4
* Relaxed doctest upper bound once more, see [stackage issue 2663](https://github.com/fpco/stackage/issues/2663#issuecomment-319880160).

## 0.3.2.3
* Relaxed doctest upper bound.

## 0.3.2.2
* Relaxed criterion upper bound.

## 0.3.2.1
* Relaxed optparse-applicative upper bound.

## 0.3.2
* Fixed some dimensions minifying incorrectly.
* Fixed some Eq instances.
* <An+B> values data type modified to disallow invalid values. This makes the
  data type safer, also simplifying the Quickcheck Arbitrary instance.
* Improved test coverage.

## 0.3.1.3
* Added support for `@supports` rules, and a slight minification for them: it
  removes adjacent negations, i.e.: @supports not (not ...) gets turn into
  @supports ....
* Fixed a small bug with `:lang()` where spaces before the right parenthesis
  weren't being removed.
* Improved test coverage.

## 0.3.0.1
Initial release
