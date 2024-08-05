﻿using Common.Tool;
using System;
using System.Globalization;
using System.Windows.Data;
using System.Windows.Media;


namespace IOBoard.View.Converter
{
    public class NullableBoolToBrushConverter : IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        {
            bool? b = (bool?)value;

            if (b.IsNull())
                return new SolidColorBrush(Colors.Yellow);
            if (b == true)
                return new SolidColorBrush(Colors.Green);

            return new SolidColorBrush(Colors.Red);
        }

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        {
            throw new NotImplementedException();
        }
    }
}
