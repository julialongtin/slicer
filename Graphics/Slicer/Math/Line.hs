{-
 - Copyright 2016 Noah Halford and Catherine Moresco
 - Copyright 2019 Julia Longtin
 -
 - This program is free software: you can redistribute it and/or modify
 - it under the terms of the GNU Affero General Public License as published by
 - the Free Software Foundation, either version 3 of the License, or
 - (at your option) any later version.
 -
 - This program is distributed in the hope that it will be useful,
 - but WITHOUT ANY WARRANTY; without even the implied warranty of
 - MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 - GNU Affero General Public License for more details.

 - You should have received a copy of the GNU Affero General Public License
 - along with this program.  If not, see <http://www.gnu.org/licenses/>.
 -}

{- The purpose of this file is to hold line based arithmatic. -}

-- for adding Generic and NFData to Line.
{-# LANGUAGE DeriveGeneric, DeriveAnyClass #-}

module Graphics.Slicer.Math.Line (Line(Line), point, slope, lineIntersection, lineFromEndpoints, endpoint, midpoint, flipLine, pointSlopeLength, combineLines, canCombineLines, perpendicularBisector, pointAtZValue, shortenLineBy, makeLines, lineSlope, Direction(Positive, Negative), Slope(IsOrigin, OnXAxis, OnYAxis, HasSlope), combineConsecutiveLines) where

import Prelude ((/), (<), (>), (*), ($), sqrt, (+), (-), otherwise, (&&), (<=), (==), Eq, length, head, tail, Bool(False), (/=), (++), last, init, (<$>))

import Data.Maybe (Maybe(Just, Nothing))

import Data.List.Ordered (foldt)

import GHC.Generics (Generic)

import Control.DeepSeq (NFData)

import Graphics.Slicer.Definitions (ℝ)

import Graphics.Slicer.Math.Definitions (Point(Point))

import Graphics.Slicer.Math.Point (twoDCrossProduct, scalePoint, addPoints, distance, magnitude)

-- Data structure for a line segment in the form (x,y,z) = (x0,y0,z0) + t(mx,my,mz)
-- t should run from 0 to 1, so the endpoints are (x0,y0,z0) and (x0 + mx, y0 + my, z0 + mz)
-- note that this means slope and endpoint are entangled. make sure to derive what you want before using slope.
data Line = Line { point :: Point, slope :: Point }
  deriving (Generic, NFData)

-- a difference that makes no difference is no difference..
-- FIXME: magic numbers.
instance Eq Line where
      (==) (Line p1 m1) (Line p2 m2) = distance p1 p2 < 0.0001 && distance m1 m2 < 0.0001

-- Line intersection algorithm from http://stackoverflow.com/questions/563198/how-do-you-detect-where-two-line-segments-intersect
lineIntersection :: Line -> Line -> Maybe Point
lineIntersection (Line p r) (Line q s)
  | twoDCrossProduct r s == 0 = Nothing
  | 0 <= t && t <= 1 && 0 <= u && u <= 1 = Just (addPoints p (scalePoint t r))
  | otherwise = Nothing
  where t = twoDCrossProduct (addPoints q (scalePoint (-1) p)) s / twoDCrossProduct r s
        u = twoDCrossProduct (addPoints q (scalePoint (-1) p)) r / twoDCrossProduct r s

-- Create a line given its endpoints
lineFromEndpoints :: Point -> Point -> Line
lineFromEndpoints p1 p2 = Line p1 (addPoints (scalePoint (-1) p1) p2)

-- Get the other endpoint
endpoint :: Line -> Point
endpoint l = addPoints (point l) (slope l)

-- Midpoint of a line
midpoint :: Line -> Point
midpoint (Line p s) = addPoints p (scalePoint 0.5 s)

-- Express a line in terms of the other endpoint
flipLine :: Line -> Line
flipLine l@(Line _ s) = Line (endpoint l) (scalePoint (-1) s)

-- Given a list of points (in order), construct lines that go between them. Note
-- that this is NOT cyclic, which is why we make sure we have cyclicity in readFacet
makeLines :: [Point] -> [Line]
makeLines l
  | length l < 2 = []
  | otherwise = lineFromEndpoints (head l) (head l') : makeLines l'
  where l' = tail l

data Direction =
    Positive
  | Negative
  deriving Eq

data Slope =
    IsOrigin
  | OnXAxis Direction
  | OnYAxis Direction
  | HasSlope ℝ
  deriving Eq

-- FIXME: better way to handle no angle, or alignment on an axis.
lineSlope :: Point -> Slope
lineSlope (Point (x,y,_))
  | x == 0 && y == 0 = IsOrigin
  | x == 0 && y > 0 = OnXAxis Positive
  | x == 0 && y < 0 = OnXAxis Positive
  | x > 0 && y == 0 = OnYAxis Positive
  | x < 0 && y == 0 = OnYAxis Positive
  | otherwise = HasSlope $ y / x

-- Given a Point and Slope, make a line with that slope from that point of a specified
-- distance, in the same z plane.
-- FIXME: magic numbers.
pointSlopeLength :: Point -> Slope -> ℝ -> Line
pointSlopeLength p1 IsOrigin _ = Line p1 p1
pointSlopeLength p1 (OnXAxis Positive) dist = Line p1 (Point (dist,0,0))
pointSlopeLength p1 (OnXAxis Negative) dist = Line p1 (Point (-dist,0,0))
pointSlopeLength p1 (OnYAxis Positive) dist = Line p1 (Point (0,dist,0))
pointSlopeLength p1 (OnYAxis Negative) dist = Line p1 (Point (0,-dist,0))
pointSlopeLength p1 (HasSlope sl) dist = Line p1 s
  where s = scalePoint scale $ Point (1,yVal,0)
        yVal = sl
        scale = dist / sqrt (1 + yVal*yVal)

-- Combine consecutive lines. expects lines with their end points connecting, EG, a contour fenerated by makeContours.
combineConsecutiveLines :: [Line] -> [Line]
combineConsecutiveLines lines
  | length lines > 1 = foldt combine [last lines] ((:[]) <$> init lines)
  | otherwise = lines
  where
    combine :: [Line] -> [Line] -> [Line]
    combine l1 [] = l1 
    combine l1 (l2:ls) = if canCombineLines (last l1) (l2) then (init l1) ++ (combineLines (last l1) l2):ls else l1 ++ l2:ls

-- Combine lines (p1 -- p2) (p3 -- p4) to (p1 -- p4). We really only want to call this
-- if p2 == p3 and the lines are parallel (see canCombineLines)
combineLines :: Line -> Line -> Line
combineLines (Line p _) l2 = lineFromEndpoints p (endpoint l2)

-- Determine if two lines can be combined
canCombineLines :: Line -> Line -> Bool
canCombineLines l1@(Line _ s1) (Line p2 s2)
  | lineSlope s1 /= lineSlope s2 = False
  | otherwise = endpoint l1 == p2

-- Construct a perpendicular bisector of a line (with the same length, assuming
-- a constant z value)
perpendicularBisector :: Line -> Line
perpendicularBisector l@(Line p s@(Point (_,y,_)))
  | y == 0 = Line (midpoint l) (Point (0, magnitude s, 0))
  | otherwise = pointSlopeLength (midpoint l) m (distance p (endpoint l))
  where
    m = lineSlope s

-- Find the point on a line for a given Z value. Note that this evaluates to Nothing
-- in the case that there is no point with that Z value, or if that is the only
-- Z value present in that line. The latter should be okay because the properties
-- of our meshes mean that the two endpoints of our line should be captured by
-- the other two segments of a triangle.
pointAtZValue :: Line -> ℝ -> Maybe Point
pointAtZValue (Line p m) v
  | 0 <= t && t <= 1 = Just $ addPoints p (scalePoint t m)
  | otherwise = Nothing
  where
    t = (v - zOf p) / zOf m
    zOf :: Point ->  ℝ
    zOf (Point (_,_,z)) = z

-- shorten line by an amount in millimeters on each end
shortenLineBy :: ℝ -> Line -> Line
shortenLineBy amt line = Line newStart newSlope
  where pct = amt / magnitude (slope line)
        newStart = addPoints (point line) $ scalePoint pct (slope line)
        newSlope = scalePoint (1 - 2 * pct) (slope line)
                                                    
