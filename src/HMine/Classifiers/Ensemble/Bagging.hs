{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE UndecidableInstances #-}

module HMine.Classifiers.Ensemble.Bagging
    where

import Control.DeepSeq
import Control.Monad
import Control.Monad.Random
import Data.Hashable

import HMine.Algebra
import HMine.Classifiers.Ensemble
import HMine.Classifiers.TypeClasses
import HMine.DataContainers

-------------------------------------------------------------------------------
-- BaggingParams

data BaggingParams modelparams = BaggingParams 
    { bagProb :: Double 
    , bagSeed :: Int
    , paramsL :: [modelparams]
    }
    deriving (Show,Read,Eq)
    
instance (NFData modelparams) => NFData (BaggingParams modelparams) where
    rnf params = deepseq (rnf bagProb) (rnf paramsL)
    
defBaggingParams :: Int -> Int -> modelparams -> BaggingParams modelparams
defBaggingParams seed num modelparams = BaggingParams
    { bagProb = 2/(fromIntegral num)
    , bagSeed = seed
    , paramsL = replicate num modelparams
    }

-------------------------------------------------------------------------------
-- Ensemble instances

instance 
    ( Hashable label
    , OnlineTrainer modelparams model label
    ) =>
        BatchTrainer (BaggingParams modelparams) (Ensemble (BaggingParams modelparams) model label) label 
            where
              
    trainBatch = trainOnline

-- instance (Eq modelparams, Semigroup model) => Semigroup (Ensemble (BaggingParams modelparams) model) where
--     
--     (<>) (Ensemble ens1 params1) (Ensemble ens2 params2) = Ensemble (map merge $ zip ens1 ens2) params'
--         where
--             merge ((w1,m1),(w2,m2)) = ((w1+w2)/2,m1<>m2)
--             params' = if params1/=params2
--                          then error "Ensemble.semigroup <>: different parameters"
--                          else params1

instance 
    ( Hashable label
    , OnlineTrainer modelparams model label
    ) =>
        OnlineTrainer (BaggingParams modelparams) (Ensemble (BaggingParams modelparams) model label) label 
            where
        
--     emptyModel :: DataDesc -> modelparams -> model
    emptyModel desc params = Ensemble
        { ensembleL = map (\x -> (1,emptyModel desc x)) (paramsL params)
        , ensembleDataDesc = desc
        , ensembleParams = params
        }

--     add1dp :: DataDesc -> modelparams -> model -> LDPS label -> model
    add1dp desc modelparams ens ldp = do
        let boolL = genBoolL ens ldp
        add1dpL <- mapM (\(baseparams,oldens) -> add1dp desc baseparams oldens ldp) $ zip (paramsL $ ensembleParams ens) (map snd $ ensembleL ens)
        let ens'=map (\(b,(x,(d,y)))->if b; then (d,x); else (d,y)) $ zip boolL $ zip add1dpL $ ensembleL ens
        return $ ens { ensembleL = ens' }

genBoolL :: (Hashable label) => (Ensemble (BaggingParams modelparams) model label) -> LDPS label -> [Bool]
genBoolL ens ldp = flip evalRand (mkStdGen $ combine (bagSeed $ ensembleParams ens) (hash ldp)) $ 
            replicateM (length $ ensembleL ens) $ fmap (<(bagProb $ ensembleParams ens)) $ getRandomR (0,1)
            