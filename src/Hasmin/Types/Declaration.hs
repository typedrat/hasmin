{-# LANGUAGE OverloadedStrings #-}
-----------------------------------------------------------------------------
-- |
-- Module      : Hasmin.Types.Declaration
-- Copyright   : (c) 2017 Cristian Adrián Ontivero
-- License     : BSD3
-- Stability   : experimental
-- Portability : non-portable
--
-----------------------------------------------------------------------------
module Hasmin.Types.Declaration (
    Declaration(..), clean
    ) where

import Control.Monad.Reader
import Control.Arrow (first)
import Data.Map.Strict (Map)
import Data.Monoid ((<>))
import Data.Maybe (fromMaybe)
import Data.List (find, delete, minimumBy, (\\))
import Data.Text (Text) 
import Data.Text.Lazy.Builder (singleton, fromText)
import Hasmin.Config
import Hasmin.Types.Class
import Hasmin.Types.Value
import Hasmin.Types.Dimension
import Hasmin.Types.Numeric
import Hasmin.Types.TransformFunction
import Hasmin.Types.PercentageLength
import Hasmin.Types.Position
import Hasmin.Types.BgSize
import Hasmin.Properties
import Hasmin.Utils
import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import Text.PrettyPrint.Mainland (Pretty, ppr, strictText, colon, (<+>))

data Declaration = Declaration { propertyName :: Text 
                               , valueList :: Values
                               , isImportant :: Bool  -- ends with !important
                               , hasIEhack :: Bool    -- ends with \9
                               } deriving (Eq, Show)

instance Pretty Declaration where
  ppr (Declaration p v i h) = strictText p <> colon <+> ppr v <> imp
                           <> (if h then " \\9" else mempty)
    where imp | i         = strictText " !important" 
              | otherwise = mempty
instance ToText Declaration where
  toBuilder (Declaration p vs i h) = fromText p <> singleton ':' 
      <> toBuilder vs <> imp <> (if h then " \\9" else mempty)
    where imp | i         = "!important" 
              | otherwise = mempty

instance Minifiable Declaration where
  minifyWith d@(Declaration p vs _ _) = do
      minifiedValues <- minifyWith vs
      conf <- ask
      let name   = if shouldLowercase conf
                      then T.toLower p
                      else p
          newDec = d {propertyName = name, valueList = minifiedValues }
      case Map.lookup (T.toCaseFold p) propertyOptimizations of
           Just f  -> propertyTraits newDec >>= f
           Nothing -> propertyTraits newDec

propertyTraits :: Declaration -> Reader Config Declaration
propertyTraits d@(Declaration p _ _ _) = do
    conf <- ask
    pure $ if shouldUsePropertyTraits conf
              then case Map.lookup (T.toCaseFold p) propertiesTraits of
                     Just (vals, inhs) -> minifyDec d vals inhs
                     Nothing           -> d
              else d

-- Map relating properties with specific functions to optimize them
propertyOptimizations :: Map Text (Declaration -> Reader Config Declaration)
propertyOptimizations = Map.fromList
  [("transform",         combineTransformFunctions)
  ,("-webkit-transform", combineTransformFunctions)
  ,("-moz-transform",    combineTransformFunctions)
  -- ,("font",              optimizeValues optimizeFontFamily)
  ,("font-family",       optimizeValues optimizeFontFamily)
  ,("font-weight",       fontWeightOptimizer)

  ,("background-size",            nullPercentageToLength)
  ,("width",                      nullPercentageToLength)
  ,("perspective-origin",         nullPercentageToLength)
  ,("-o-perspective-origin",      nullPercentageToLength)
  ,("-moz-perspective-origin",    nullPercentageToLength)
  ,("-webkit-perspective-origin", nullPercentageToLength)
  ,("background-position",        nullPercentageToLength)
  ,("top",                        nullPercentageToLength)
  ,("right",                      nullPercentageToLength)
  ,("bottom",                     nullPercentageToLength)
  ,("left",                       nullPercentageToLength)
  ,("border-color",               pure . reduceTRBL)
  ,("border-width",               pure . reduceTRBL)
  ,("border-style",               pure . reduceTRBL)
  ,("padding",                    nullPercentageToLength >=> pure . reduceTRBL)
  ,("padding-top",                nullPercentageToLength)
  ,("padding-right",              nullPercentageToLength)
  ,("padding-bottom",             nullPercentageToLength)
  ,("padding-left",               nullPercentageToLength)
  ,("margin-top",                 nullPercentageToLength)
  ,("margin-right",               nullPercentageToLength)
  ,("margin-bottom",              nullPercentageToLength)
  ,("margin-left",                nullPercentageToLength)
  ,("margin",                     nullPercentageToLength >=> pure . reduceTRBL)
  ,("grid-row-gap",               nullPercentageToLength)
  ,("grid-column-gap",            nullPercentageToLength)
  ,("line-height",                nullPercentageToLength)
  ,("min-height",                 nullPercentageToLength)
  ,("max-width",                  nullPercentageToLength)
  ,("min-width",                  nullPercentageToLength)
  ,("text-indent",                nullPercentageToLength)
  ,("text-transform",             nullPercentageToLength)
  ,("font-size",                  nullPercentageToLength)
  ,("word-spacing",               nullPercentageToLength >=> replaceWithZero "normal")
  ,("vertical-align",             nullPercentageToLength >=> replaceWithZero "baseline")
  -- ,("outline",         replaceWithZero "none")
  -- ,("border",          replaceWithZero "none")
  -- ,("background",      replaceWithZero "0 0")
  ,("transform-origin",         optimizeTransformOrigin >=> nullPercentageToLength)
  ,("-o-transform-origin",      optimizeTransformOrigin >=> nullPercentageToLength)
  ,("-moz-transform-origin",    optimizeTransformOrigin >=> nullPercentageToLength)
  ,("-ms-transform-origin",     optimizeTransformOrigin >=> nullPercentageToLength)
  ,("-webkit-transform-origin", optimizeTransformOrigin >=> nullPercentageToLength)
  ]

-- Generic function to map some optimization to a property's values.
optimizeValues :: (Value -> Reader Config Value) 
               -> Declaration -> Reader Config Declaration
optimizeValues f d@(Declaration _ vs _ _) = do
    newV <- mapValues f vs
    pure $ d {valueList = newV }

-- converts 0% into 0 (of type <length>)
-- Do NOT use it with height and max-height, since 0% /= 0
nullPercentageToLength :: Declaration -> Reader Config Declaration
nullPercentageToLength d = do 
    conf <- ask
    if shouldConvertNullPercentages conf
       then optimizeValues f d
       else pure d
  where f :: Value -> Reader Config Value
        f (PositionV p@(Position _ a _ b)) = pure . PositionV $
            let stripPercentage Nothing  = Nothing
                stripPercentage (Just x) = if isZero x 
                                              then l0
                                              else Just x
            in p { offset1 = stripPercentage a, offset2 = stripPercentage b }
        f (PercentageV p) = pure $ zeroPercentageToLength p
          where zeroPercentageToLength :: Percentage -> Value
                zeroPercentageToLength 0 = DistanceV (Distance 0 Q)
                zeroPercentageToLength x = PercentageV x
        f (BgSizeV (BgSize x y)) = pure . BgSizeV $ BgSize (zeroPerToLength x) (fmap zeroPerToLength y)
          where zeroPerToLength (Left (Left 0)) = Left $ Right (Distance 0 Q)
                zeroPerToLength z = z 
        f x = pure x 

-- For word-spacing, normal computes to 0.
-- For vertical-align, baseline is the same as 0.
--
-- Careful: don't apply it for letter-spacing because there is a slight
-- difference between normal and 0 for that property!
replaceWithZero :: Text -> Declaration -> Reader Config Declaration
replaceWithZero s d@(Declaration p (Values v vs) _ _)
    | not (null vs) = pure d -- Some error occured, since there should be only one value
    | otherwise     = 
        case Map.lookup (T.toCaseFold p) propertiesTraits of
          Just (iv, inhs) -> if f iv inhs == mkOther s
                                then pure $ d { valueList = Values (DistanceV (Distance 0 Q)) [] }
                                else pure d
          Nothing         -> pure d
  where f (Just (Values x _)) inh
          | v == Initial || v == Unset && not inh = x
          | otherwise                             = v 
        f _ _ = v

-- Converts the keywords "normal" and "bold" to 400 and 700, respectively.
fontWeightOptimizer :: Declaration -> Reader Config Declaration
fontWeightOptimizer = optimizeValues f 
  where f :: Value -> Reader Config Value
        f x@(Other t) = do
          conf <- ask
          pure $ if shouldMinifyFontWeight conf
                    then replaceForSynonym t
                    else x
        f x = pure x 

        replaceForSynonym :: TextV -> Value
        replaceForSynonym t
          | t == TextV "normal" = NumberV 400
          | t == TextV "bold"   = NumberV 700
          | otherwise           = Other t

optimizeTransformOrigin :: Declaration -> Reader Config Declaration
optimizeTransformOrigin d@(Declaration _ v _ _) = do
    conf <- ask
    pure $ if shouldMinifyTransformOrigin conf
              then d { valueList = optimizeTransformOrigin' v}
              else d

optimizeTransformOrigin' :: Values -> Values
optimizeTransformOrigin' v =
    mkValues $ case valuesToList v of
                 [x, y, z] -> if isZeroVal z
                                 then transformOrigin2 x y
                                 else transformOrigin3 x y z
                 [x, y]    -> transformOrigin2 x y
                 [x]       -> transformOrigin1 x
                 x         -> x

-- isZeroVal is needed because we are using a generic parser for
-- transform-origin, so 0 parses as a number instead of a distance.
isZeroVal :: Value -> Bool
isZeroVal (DistanceV (Distance 0 Q))  = True
isZeroVal (NumberV (Number 0))        = True
isZeroVal (PercentageV 0)             = True
isZeroVal _                           = False

transformOrigin1 :: Value -> [Value]
transformOrigin1 (Other "top")    = [Other "top"]
transformOrigin1 (Other "bottom") = [Other "bottom"]
transformOrigin1 (Other "right")  = [PercentageV (Percentage 100)]
transformOrigin1 (Other "left")   = [DistanceV (Distance 0 Q)]
transformOrigin1 (Other "center") = [PercentageV (Percentage 50)]
transformOrigin1 (PercentageV 0)  = [DistanceV (Distance 0 Q)]
transformOrigin1 x                = [x]

transformOrigin2 :: Value -> Value -> [Value]
transformOrigin2 x y
    | equalsCenter x     = firstIsCenter
    | equalsCenter y     = secondIsCenter
    | isYoffsetKeyword x = fmap convertValue [y,x]
    | isXoffsetKeyword y = fmap convertValue [y,x]
    | otherwise          = fmap convertValue [x,y]
  where firstIsCenter
            | equalsCenter y           = [per50]
            | isYoffsetKeyword y       = [y]
            | y == per100              = [Other "bottom"]
            | isZeroVal y              = [Other "top"]
            | isPercentageOrDistance y = [per50, y]
            | otherwise                = transformOrigin1 y
        secondIsCenter
            | equalsCenter x                                 = [per50]
            | isYoffsetKeyword x || isPercentageOrDistance x = [x]
            | otherwise                                      = transformOrigin1 x
        isPercentageOrDistance (PercentageV _) = True
        isPercentageOrDistance (DistanceV _)   = True
        isPercentageOrDistance _               = False
        equalsCenter a     = a == Other "center" || a == per50
        isXoffsetKeyword a = a == Other "left" || a == Other "right"
        isYoffsetKeyword a = a == Other "top" || a == Other "bottom"
        per50 = PercentageV $ Percentage 50
        per100 = PercentageV $ Percentage 100
        convertValue (Other t) = fromMaybe (Other t) (Map.lookup (getText t) equivalences)
        convertValue n@(PercentageV p) = if p == 0
                              then DistanceV (Distance 0 Q)
                              else n
        convertValue i = i

transformOrigin3 :: Value -> Value -> Value -> [Value]
transformOrigin3 x y z
    | x == Other "top" || x == Other "bottom" 
      || y == Other "left" || y == Other "right" = fmap replaceKeywords [y, x, z]
    | otherwise = fmap replaceKeywords [x, y, z]
  where replaceKeywords :: Value -> Value
        replaceKeywords (Other t) = fromMaybe x (Map.lookup (getText t) equivalences)
        replaceKeywords e = e

-- transform-origin keyword meanings.
equivalences :: Map Text Value
equivalences = Map.fromList [("top", DistanceV (Distance 0 Q))
                            ,("right", PercentageV (Percentage 100))
                            ,("bottom", PercentageV (Percentage 100))
                            ,("left", DistanceV (Distance 0 Q))
                            ,("center", PercentageV (Percentage 50))] 


-- | Minifies a declaration, based on the property's specific traits (i.e. if
-- it inherits or not, and what its initial value is), and the chosen
-- configurations.
minifyDec :: Declaration -> Maybe Values -> Bool -> Declaration
minifyDec d@(Declaration p vs _ _) mv inherits =
    case mv of 
      -- Use the found initial values to try to reduce the declaration
      Just vals ->
          case Map.lookup (T.toCaseFold p) declarationExceptions of
            -- Use a specific function to reduce the property if
            -- needed, otherwise use the general property reducer
            Just f  -> f d vals inherits
            Nothing -> reduceDeclaration d vals inherits
      -- Property with no defined initial values. Try to reduce css-wide keywords
      Nothing   -> 
          if not inherits && vs == initial || inherits && vs == inherit
             then d { valueList = unset }
             else d

unset :: Values
unset = Values Unset mempty

initial :: Values
initial = Values Initial mempty

inherit :: Values
inherit = Values Inherit mempty

-- Map of property specific reducers, for properties that don't fit in the
-- normal declaration minification scheme and need special treatment.
declarationExceptions :: Map Text (Declaration -> Values -> Bool -> Declaration)
declarationExceptions = Map.fromList $ map (first T.toCaseFold)
  [("background-size",         backgroundSizeReduce)
  ,("-webkit-background-size", backgroundSizeReduce)
  ,("font-synthesis",          fontSynthesisReduce)
  ]

combineTransformFunctions :: Declaration -> Reader Config Declaration
combineTransformFunctions d@(Declaration _ vs _ _) = do
    combinedFuncs <- combine $ fmap (\(TransformV x) -> x) tfuncs 
    let newVals = fmap TransformV combinedFuncs ++ (decValues \\ tfuncs)
    pure $ d { valueList = mkValues newVals}
  where decValues     = valuesToList vs
        tfuncs = filter isTransformFunction decValues
        isTransformFunction (TransformV _) = True
        isTransformFunction _              = False

backgroundSizeReduce :: Declaration -> Values -> Bool -> Declaration
backgroundSizeReduce d@(Declaration _ vs _ _) initVals inherits =
    case valuesToList vs of
      [v1,v2] -> if v2 == mkOther "auto"
                    then d { valueList = mkValues [v1] }
                    else d
      _       -> d { valueList = shortestEquiv vs initVals inherits }

fontSynthesisReduce :: Declaration -> Values -> Bool -> Declaration
fontSynthesisReduce d@(Declaration _ vs _ _) initVals inherits =
    case valuesToList initVals \\ valuesToList vs of
      [] -> d {valueList = initial} -- "initial" is shorter than "weight style"
      _  -> d {valueList = shortestEquiv vs initVals inherits}

-- Function to reduce the great mayority of properties. Requires that:
-- 1. The order between values doesn't matter, which is true for most
--    properties because they take only one value.
-- 2. Any default value may be removed, which tends to hold for shorthands
--    because the default value is used when it isn't present. An example of a
--    property that qualifies is border-bottom, and one that doesn't is
--    font-synthesis (because it isn't a shorthand).
reduceDeclaration :: Declaration -> Values -> Bool -> Declaration
reduceDeclaration d@(Declaration _ vs _ _) initVals inherits = 
    case analyzeValueDifference vs initVals of
      Just v  -> d {valueList = shortestEquiv v shortestInitialValue inherits}
      Nothing -> d {valueList = minVal inherits shortestInitialValue}
  where comparator x y = compare (textualLength x) (textualLength y)
        shortestInitialValue = mkValues [minimumBy comparator (valuesToList initVals)]

-- If the value was a css-wide keyword, return the shortest between css-wide
-- keywords and the shortest initial value for the property.
-- Otherwise, no property specific reduction could be done, so just return the
-- values.
shortestEquiv :: Values -> Values -> Bool -> Values
shortestEquiv vs siv inherits
    | inherits     && vs == inherit                = unset
    | not inherits && vs == unset || vs == initial = minVal inherits siv
    | otherwise = vs

-- Returns the minimum value (in character length) between the shortest initial
-- value, and the shortest css-wide keyword (initial or unset)
minVal :: Bool -> Values -> Values
minVal inherits vs
    | textualLength globalKeyword <= textualLength vs = globalKeyword
    | otherwise                                       = vs
  where globalKeyword = mkValues [if not inherits then Unset else Initial]
    
-- Substract declaration values to the property's initial value list.
-- If nothing remains (i.e. every value declared was an initial one and may be
-- left implicit), then just replace it with whatever initial value is the
-- shortest, otherwise whatever remains is the shortest equivalent declaration.
analyzeValueDifference :: Values -> Values -> Maybe Values
analyzeValueDifference vs initVals = 
    case valuesDifference of
      [] -> Nothing -- every value was an initial one
      _  -> Just $ mkValues valuesDifference -- At least a value wasn't an initial one, or it was a css-wide keyword
  where valuesDifference = valuesToList vs \\ valuesToList initVals

-- Removes longhand rules overwritten by their shorthand further down in the
-- declaration list, and merges shorthand declarations with longhand properties
-- later declared.
clean :: [Declaration] -> [Declaration]
clean [] = []
clean (d:ds) =
    let (newD, newDs) = solveClashes ds d pinfo
    in case newD of
         Just x  -> x : clean newDs
         Nothing -> clean newDs -- drop and keep cleaning
  where pinfo = fromMaybe (PropertyInfo mempty mempty) -- No info on the property, use an empty one.
                  (Map.lookup (propertyName d) shorthandAndLonghandsMap)

-- Given a declaration, if it is a shorthand and it has a corresponding
-- longhand later in the list, merges them. If it is a longhand overwritten by
-- a shorthand, it deletes it. Otherwise, it keeps the value. In any case, it
-- returns the new list to analyze and (if any) the value to keep.
solveClashes :: [Declaration] -> Declaration 
             -> PropertyInfo -> (Maybe Declaration, [Declaration])
solveClashes ds = solveClashes' ds ds

-- Local function, only to be called by solveClashes
solveClashes' :: [Declaration] -> [Declaration] -> Declaration
              -> PropertyInfo -> (Maybe Declaration, [Declaration])
solveClashes' newDs []            dec _ = (Just dec, newDs)
solveClashes' newDs (laterDec:ds) dec pinfo
    -- Do not remove vendor-prefixed values, which are probably fallbacks.
    | hasVendorPrefix dec      = (Just dec, newDs)
    | hasVendorPrefix laterDec || hasIEhack dec /= hasIEhack laterDec = 
        solveClashes' newDs ds dec pinfo
    | propertyName laterDec `elem` subproperties pinfo =
        attemptMerge newDs ds dec laterDec pinfo
    | propertyName laterDec `elem` overwrittenBy pinfo =
        if isImportant dec && (not . isImportant) laterDec
           -- important LH with a non-important SH later, or only one of the
           -- two has the \9 ie hack; keep analyzing
           then solveClashes' newDs ds dec pinfo
           -- longhand overwritten by a shorthand; drop it
           else (Nothing, newDs)
    | propertyName dec == propertyName laterDec = {- && dec can be dropped (consider background-image!) -}
        if isImportant dec && (not . isImportant) laterDec
           -- drop non-important one; keep analyzing
           then solveClashes' (delete laterDec newDs) ds dec pinfo
           -- same property twice, drop the overwritten one
           else (Nothing, newDs)
    | otherwise = solveClashes' newDs ds dec pinfo -- keep analyzing the rest

hasVendorPrefix :: Declaration -> Bool
hasVendorPrefix (Declaration _ vs _ _) = any isVendorPrefixedValue $ valuesToList vs

isVendorPrefixedValue :: Value -> Bool
isVendorPrefixedValue (Other t)         = T.isPrefixOf "-" $ getText t
isVendorPrefixedValue (GradientV t _)   = T.isPrefixOf "-" t
isVendorPrefixedValue (GenericFunc t _) = T.isPrefixOf "-" t
isVendorPrefixedValue _                 = False

attemptMerge :: [Declaration] -> [Declaration] -> Declaration
             -> Declaration -> PropertyInfo 
             -> (Maybe Declaration, [Declaration])
attemptMerge newDs ds dec laterDec pinfo =
    case merge dec laterDec of
      -- Put the merged result back on the list; see if any other
      -- property also conflicts
      Just m -> (Nothing, m : delete dec (delete laterDec newDs))
      -- Couldn't merge, just keep analyzing
      Nothing -> solveClashes' newDs ds dec pinfo

-- TODO: make it such that the order of parameters doesn't matter
-- First declaration = shorthand
merge :: Declaration -> Declaration -> Maybe Declaration
merge d1@(Declaration p1 _ _ _) d2@Declaration{} = do
    mergeFunction <- Map.lookup p1 propertyMergers
    mergeFunction d1 d2
  where propertyMergers :: Map Text (Declaration -> Declaration -> Maybe Declaration)
        propertyMergers = Map.fromList [("margin",       mergeIntoTRBL)
                                       ,("padding",      mergeIntoTRBL)
                                       ,("border-color", mergeIntoTRBL)
                                       ,("border-width", mergeIntoTRBL)
                                       ,("border-style", mergeIntoTRBL)
                                       --,("animation", 
                                       --,("background",
                                       --,("background-position", 
                                       --,("border",
                                       --,("border-bottom", 
                                       --,("border-image",
                                       --,("border-left", 
                                       --,("border-radius"
                                       --,("border-right",
                                       --,("border-top"
                                       --,("column-rule",
                                       --,("columns",
                                       --,("flex",  
                                       --,("flex-flow",
                                       --,("font",
                                       --,("grid",
                                       --,("grid-area"
                                       --,("grid-column"
                                       --,("grid-gap",
                                       --,("grid-row",
                                       --,("grid-template",
                                       --,("list-style",
                                       --,("mask", 
                                       --,("outline",
                                       --,("padding",
                                       --,("text-decoration", 
                                       --,("text-emphasis"
                                       --,("transition",
                                       ]


-- TODO: consider the check in retDec. We aren't taking the minified length,
-- only the one as it is. Ideally, it would take the length of the minified
-- result, according to the program arguments.
mergeIntoTRBL :: Declaration       -- ^ A margin declaration
              -> Declaration       -- ^ Any of the margin longhands (e.g.: margin-top)
              -> Maybe Declaration -- ^ If successful, the combination of both
mergeIntoTRBL d1@(Declaration _ (Values v1 vs) i1 h1) d2@(Declaration p2 (Values v2 _) i2 h2)
    | h1 || h2     = Nothing -- TODO handle ie hacks
    | i1 && not i2 = Just $ reduceTRBL d1 -- margin:6px !important;margin-top:0; --> margin:6px !important
    | not i1 && i2 = Nothing -- margin:6px;margin-top:0!important; --> stays the same
    | otherwise    = do
          (_,index) <- find (\(x,_) -> T.isInfixOf x (T.toCaseFold p2)) indexTable
          let mkDec ys  = d1 {valueList = mkValues $ replaceAt index v2 ys}
              retDec ys = let mergedDec = reduceTRBL (mkDec ys)
                          in if textualLength mergedDec <= originalLength
                                then Just mergedDec
                                else Nothing
          case trblValues of
                    [_,_,_,_] -> retDec trblValues
                    [t,r,b]   -> retDec [t,r,b,r]
                    [t,r]     -> retDec [t,r,t,r]
                    [t]       -> retDec [t,t,t,t]
                    _         -> Nothing -- E.g.: an iehack read as a value.
  where originalLength = textualLength d1 + textualLength d2 + 1 -- The (+1) is because of the ;
        trblValues     = v1 : map snd vs
        indexTable     = fmap (first T.toCaseFold) [("top",    0)
                                                   ,("right",  1)
                                                   ,("bottom", 2)
                                                   ,("left",   3)]

-- E.g.: margin: 6px 6px 6px 6px;  --> margin: 6px;
--       margin: 1px 0 2px 0;      --> margin: 1px 0 2px;
-- can be used with "border-image-outset" too.
reduceTRBL :: Declaration -> Declaration
reduceTRBL d@(Declaration _ (Values v1 vs) _ _) =
    case v1:map snd vs of
      [t,r,b,l] -> reduce4 t r b l
      [t,r,b]   -> reduce3 t r b
      [t,r]     -> reduce2 t r
      _         -> d 
  where reduce4 tv rv bv lv
            | lv == rv  = reduce3 tv rv bv
            | otherwise = d
        reduce3 tv rv bv
            | tv == bv  = reduce2 tv rv
            | otherwise = d { valueList = mkValues [tv, rv, bv] }
        reduce2 tv rv
            | tv == rv  = d { valueList = mkValues [tv] }
            | otherwise = d { valueList = mkValues [tv, rv] }

-- mapValues :: (Value -> Value) -> Values -> Values
mapValues :: (Value -> Reader Config Value) -> Values -> Reader Config Values
mapValues f (Values v1 vs) = do
    x <- f v1
    xs <- (mapM . mapM) f vs
    pure $ Values x xs
