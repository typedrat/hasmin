{-# LANGUAGE OverloadedStrings #-}

module Hasmin.Types.SelectorSpec where

import Test.Hspec
import Hasmin.Parser.Internal
import Hasmin.TestUtils

import Control.Monad.Reader (runReader)
import Data.Text (Text)
import Hasmin.Types.Class
import Hasmin.Config

anplusbMinificationTests :: Spec
anplusbMinificationTests =
    describe "<an+b> minification tests" $
      mapM_ (matchSpec (minify <$> selector)) anplusbMinificationTestsInfo

selectorMinificationTests :: Spec
selectorMinificationTests =
    describe "Selectors minification test" $
      mapM_ (matchSpec (minify <$> selector)) selectorTestsInfo

selectorTestsInfo :: [(Text, Text)]
selectorTestsInfo =
  [("div > p", "div>p")
  ,("div p",   "div p")
  ,("div + p", "div+p")
  ,("div ~ p", "div~p")
  ,("p::selection", "p::selection")
  ,("html:lang( 'de' )", "html:lang(de)")
  ]

anplusbMinificationTestsInfo :: [(Text, Text)]
anplusbMinificationTestsInfo =
  [(":nth-child(-1n)",      ":nth-child(-n)")
  ,(":nth-child(-n)",       ":nth-child(-n)")
  ,(":nth-child(odd)",      ":nth-child(odd)")
  ,(":nth-child(+n)",       ":nth-child(n)")
  ,(":nth-child(+1n)",      ":nth-child(n)")
  ,(":nth-child(1n+0)",     ":nth-child(n)")
  ,(":nth-child(1n-0)",     ":nth-child(n)")
  ,(":nth-child(+3n)",      ":nth-child(3n)")
  ,(":nth-child( even )",   ":nth-child(2n)")
  ,(":nth-child( 2n - 2 )", ":nth-child(2n)")
  ,(":nth-child( 2n - 4 )", ":nth-child(2n)")
  ,(":nth-child( 2n + 1 )", ":nth-child(odd)")
  ,(":nth-child( 2n - 1 )", ":nth-child(odd)")
  ,(":nth-child( 2n - 3 )", ":nth-child(odd)")
  ,(":nth-child(0n)",       ":nth-child(0)")
  ,(":nth-child(0n+0)",     ":nth-child(0)")
  ,(":nth-child(0n-0)",     ":nth-child(0)")
  ,(":nth-child(0n-1)",     ":nth-child(-1)")
  ,(":nth-child(3n-3)",     ":nth-child(3n-3)")
  ,(":nth-child(2n+4)",     ":nth-child(2n+4)")
  ,(":nth-child(+4)",       ":nth-child(4)")
  ]

attributeQuoteRemovalTest :: Spec
attributeQuoteRemovalTest =
    describe "attribute quote removal tests" $
      mapM_ (matchSpec (f <$> selector)) attributeQuoteRemovalTestInfo
  where f x = runReader (minifyWith x) defaultConfig

attributeQuoteRemovalTestInfo :: [(Text, Text)]
attributeQuoteRemovalTestInfo =
  [("[type=\"remove-double-quotes\"]", "[type=remove-double-quotes]")
  ,("[type='remove-single-quotes']",   "[type=remove-single-quotes]")
  ,("[a^='\"']", "[a^='\"']")
  ]

spec :: Spec
spec = do anplusbMinificationTests
          attributeQuoteRemovalTest
          selectorMinificationTests
          attributeQuoteRemovalTest

main :: IO ()
main = hspec spec