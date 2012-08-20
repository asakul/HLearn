{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE UndecidableInstances #-}

module HMine.Classifiers.Ensemble
    where

import Control.DeepSeq
import Control.Monad
import Control.Monad.Random
import Data.Binary
import Data.Hashable
import Data.List
import Data.List.Extras
import Data.Semigroup
import Data.Number.LogFloat
import Debug.Trace
      
import HMine.Algebra
import HMine.Base
import HMine.Classifiers.TypeClasses
import HMine.DataContainers
import HMine.MiscUtils

-------------------------------------------------------------------------------
-- ModelBox

data ModelBox label = 
    forall model .
        ( ProbabilityClassifier model label
        ) => 
    ModelBox model

instance (Label label) => ProbabilityClassifier (ModelBox label) label where
    probabilityClassify (ModelBox model) = probabilityClassify model

-------------------------------------------------------------------------------
-- Ensemble

data Ensemble modelparams model label = Ensemble 
    { ensembleL :: [(Double,model)]
    , ensembleDataDesc :: DataDesc label
    , ensembleParams :: modelparams
    }
    deriving (Show,Read,Eq)

pushClassifier :: (Double,model) -> Ensemble modelparams model label -> Ensemble modelparams model label
pushClassifier wm ens = ens { ensembleL = wm:(ensembleL ens) }

emptyEnsemble :: DataDesc label -> modelparams -> Ensemble modelparams model label
emptyEnsemble desc modelparams = Ensemble
    { ensembleL = []
    , ensembleDataDesc = desc
    , ensembleParams = modelparams
    }

instance (NFData modelparams, NFData model, NFData label) => NFData (Ensemble modelparams model label) where
    rnf ens = deepseq (rnf $ ensembleL ens) (rnf $ ensembleParams ens)

instance (Invertible model) => Invertible (Ensemble modelparams model label) where
    inverse ens = ens { ensembleL = map (\(w,m) -> (w,inverse m)) $ ensembleL ens }

instance (Label label, Eq modelparams, Semigroup model) => Semigroup (Ensemble modelparams model label) where
    
    (<>) (Ensemble ens1 desc1 params1) (Ensemble ens2 desc2 params2) = Ensemble ens' desc' params'
        where
            ens' = map merge $ zip (sort' ens1) (sort' ens2)
            sort' = sortBy (\(w1,_) (w2,_) -> compare w1 w2)
            merge ((w1,m1),(w2,m2)) = ((w1+w2)/2,m1<>m2)
            params' = if params1/=params2
                         then error "Ensemble.semigroup <>: different modelparams"
                         else params1
            desc' = if desc1 /= desc2
                       then error "Ensemble.semigroup <>: different DataDesc"
                       else desc1

-------------------------------------------------------------------------------
-- Classification

instance (Classifier model label) => Classifier (Ensemble modelparams model label) label where
    classify ens dp = argmax labelScore (labelL $ ensembleDataDesc ens)
        where 
            labelScore label = sum $ map (\(w,model) -> w*(indicator $ label==classify model dp)) $ ensembleL ens
            classifyL = map (classify . snd) $ ensembleL ens

instance ( ProbabilityClassifier model label, Eq label) => 
    ProbabilityClassifier (Ensemble modelparams model label) label where
        
    probabilityClassify (Ensemble xs desc params) dp = foldl1' combiner weightedModelL
        where
--             combiner :: (Eq label) => [(label,Probability)] -> [(label,Probability)] -> [(label,Probability)]
            combiner xs ys = map (\((l1,p1),(l2,p2))->if l1==l2
                                                         then (l1,p1+p2)
                                                         else error "Ensemble.probabilityClassify: models output different labels"
                                                         ) 
                           $ zip xs ys
                           
--             weightedModelL :: [[(label,Probability)]]
            weightedModelL = map (\(w,xs) -> map (\(l,p)->(l,(logFloat w)*p)) xs) $ zip weightL' modelL'
            
            weightL' = normalizeL weightL
            modelL' = map (flip probabilityClassify dp) modelL
            (weightL,modelL)=unzip xs