﻿using Common;
using System.Windows;


namespace ImageProcess.ContourScanner
{
    public class SamplingPointPair
    {
        public Point Brighter { get; private set; }
        public Point Darker { get; private set; }


        public SamplingPointPair(Point brighter, Point darker)
        {
            Brighter = brighter;
            Darker = darker;
        }

        public void Rotate(double angle)
        {
            Brighter = Brighter.RotatePoint(angle);
            Darker = Darker.RotatePoint(angle);
        }

        public void Add(Point point)
        {
            Brighter = Point.Add(Brighter, (Vector)point);
            Darker = Point.Add(Darker, (Vector)point);
        }

        public void Subtract(Point point)
        {
            Brighter = Point.Subtract(Brighter, (Vector)point);
            Darker = Point.Subtract(Darker, (Vector)point);
        }
    }
}