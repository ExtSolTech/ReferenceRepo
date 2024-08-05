using System;
using System.Collections.Generic;
using System.Threading;
using System.Runtime.InteropServices;
using UVCLib.DirectShow.Internals;
using UVCLib.Components.Internals;
using UVCLib.Components;
using System.Windows;
using System.Windows.Media.Imaging;


namespace UVCLib.DirectShow
{
    public class VideoCaptureDevice
    {
        public Grabber Grabber { get; private set; }
        public PropertiesModel PropertiesModel { get; private set; }
        public VideoCapability VideoResolution { get; set; } = null;
        public bool IsRunning { get; private set; }

        public VideoCapability[] VideoCapabilities
        {
            get
            {
                if(_videoCapabilities == null)
                {
                    lock(_cacheVideoCapabilities)
                    {
                        if((!string.IsNullOrEmpty(deviceMoniker)) && (_cacheVideoCapabilities.ContainsKey(deviceMoniker)))
                            _videoCapabilities = _cacheVideoCapabilities[deviceMoniker];
                    }

                    if(_videoCapabilities == null)
                    {
                        if(!IsRunning)
                            WorkerThread(false);
                        else
                        {
                            for(int i = 0; (i < 500) && (_videoCapabilities == null); i++)
                                Thread.Sleep(10);
                        }
                    }
                }

                return (_videoCapabilities != null) ? _videoCapabilities : new VideoCapability[0];
            }
        }


        string deviceMoniker;
        VideoCapability[] _videoCapabilities;
        readonly object sync = new object();
        static readonly Dictionary<string, VideoCapability[]> _cacheVideoCapabilities = new Dictionary<string, VideoCapability[]>();
        object graphObject;
        object sourceObject;
        object videoGrabberObject;
        object captureGraphObject;
        object crossbarObject;
        IMediaControl mediaControl;


        public VideoCaptureDevice(string deviceMoniker)
        {
            this.deviceMoniker = deviceMoniker;
            PropertiesModel = new PropertiesModel(this);
            Grabber = new Grabber();
        }

        public void Start() => WorkerThread(true);

        private void WorkerThread(bool runGraph)
        {
            ICaptureGraphBuilder2 captureGraph;
            IBaseFilter sourceBase;
            IFilterGraph2 graph;
            IBaseFilter videoGrabberBase;
            ISampleGrabber videoSampleGrabber;

            try
            {
                Type type = Type.GetTypeFromCLSID(Clsid.CaptureGraphBuilder2);
                
                if(type == null)
                    throw new ApplicationException("Failed creating capture graph builder");

                captureGraphObject = Activator.CreateInstance(type);
                captureGraph = (ICaptureGraphBuilder2)captureGraphObject;

                type = Type.GetTypeFromCLSID(Clsid.FilterGraph);
                
                if(type == null)
                    throw new ApplicationException("Failed creating filter graph");

                graphObject = Activator.CreateInstance(type);
                graph = (IFilterGraph2)graphObject;

                captureGraph.SetFiltergraph((IGraphBuilder)graph);

                sourceObject = FilterInfo.CreateFilter(deviceMoniker);
                
                if(sourceObject == null)
                    throw new ApplicationException("Failed creating device object for moniker");

                sourceBase = (IBaseFilter)sourceObject;

                type = Type.GetTypeFromCLSID(Clsid.SampleGrabber);

                if(type == null)
                    throw new ApplicationException("Failed creating sample grabber");

                videoGrabberObject = Activator.CreateInstance(type);
                videoSampleGrabber = (ISampleGrabber)videoGrabberObject;
                videoGrabberBase = (IBaseFilter)videoGrabberObject;

                graph.AddFilter(sourceBase, "source");
                graph.AddFilter(videoGrabberBase, "grabber_video");

                AMMediaType mediaType = new AMMediaType
                {
                    MajorType = MediaType.Video,
                    SubType = MediaSubType.RGB24
                };

                videoSampleGrabber.SetMediaType(mediaType);

                captureGraph.FindInterface(FindDirection.UpstreamOnly, Guid.Empty, sourceBase, typeof(IAMCrossbar).GUID, out crossbarObject);

                videoSampleGrabber.SetBufferSamples(false);
                videoSampleGrabber.SetOneShot(false);
                videoSampleGrabber.SetCallback(Grabber, 1);

                GetPinCapabilitiesAndConfigureSizeAndRate(captureGraph, sourceBase,
                    PinCategory.Capture, VideoResolution, ref _videoCapabilities);

                lock(_cacheVideoCapabilities)
                {
                    if((_videoCapabilities != null) && (!_cacheVideoCapabilities.ContainsKey(deviceMoniker)))
                        _cacheVideoCapabilities.Add(deviceMoniker, _videoCapabilities);
                }

                if (runGraph)
                {
                    captureGraph.RenderStream(PinCategory.Capture, MediaType.Video, sourceBase, null, videoGrabberBase);

                    if (videoSampleGrabber.GetConnectedMediaType(mediaType) == 0)
                    {
                        VideoInfoHeader vih = (VideoInfoHeader)Marshal.PtrToStructure(mediaType.FormatPtr, typeof(VideoInfoHeader));

                        Grabber.Width = vih.BmiHeader.Width;
                        Grabber.Height = vih.BmiHeader.Height;

                        mediaType.Dispose();
                    }

                    mediaControl = (IMediaControl)graphObject;
                    mediaControl.Run();
                    
                    int timeoutCounter = 0;

                    while (true)
                    {
                        Thread.Sleep(100);

                        if(Grabber.CallBackMethodIsCalled)
                        {
                            IsRunning = true;
                            break;
                        }
                        else
                        {
                            if (timeoutCounter < 30)
                                timeoutCounter++;
                            else
                                throw new Exception("Starting failed");
                        }
                    }
                }
                else
                    ReleaseComObjects();
            }

            catch 
            { 
                Stop();
            }
        }

        public void Stop()
        {
            IsRunning = false;
            Grabber.MakeSnapshot = false;
            Grabber.CallBackMethodIsCalled = false;
            
            if(mediaControl != null)
            {
                mediaControl.Stop();
                mediaControl = null;
            }

            ReleaseComObjects();
        }

        private void ReleaseComObjects()
        {
            if (graphObject != null)
            {
                Marshal.ReleaseComObject(graphObject);
                graphObject = null;
            }

            if (sourceObject != null)
            {
                Marshal.ReleaseComObject(sourceObject);
                sourceObject = null;
            }

            if (videoGrabberObject != null)
            {
                Marshal.ReleaseComObject(videoGrabberObject);
                videoGrabberObject = null;
            }

            if (captureGraphObject != null)
            {
                Marshal.ReleaseComObject(captureGraphObject);
                captureGraphObject = null;
            }

            if (crossbarObject != null)
            {
                Marshal.ReleaseComObject(crossbarObject);
                crossbarObject = null;
            }
        }

        private void SetResolution(IAMStreamConfig streamConfig, VideoCapability resolution)
        {
            if(resolution == null)
                return;

            int capabilitiesCount = 0, capabilitySize = 0;
            AMMediaType newMediaType = null;
            VideoStreamConfigCaps caps = new VideoStreamConfigCaps();

            streamConfig.GetNumberOfCapabilities(out capabilitiesCount, out capabilitySize);

            for(int i = 0; i < capabilitiesCount; i++)
            {
                try
                {
                    VideoCapability vc = new VideoCapability(streamConfig, i);

                    if(resolution == vc)
                    {
                        if(streamConfig.GetStreamCaps(i, out newMediaType, caps) == 0)
                        {
                            break;
                        }
                    }
                }

                catch { }
            }

            if(newMediaType != null)
            {
                streamConfig.SetFormat(newMediaType);
                newMediaType.Dispose();
            }
        }



        private void GetPinCapabilitiesAndConfigureSizeAndRate(ICaptureGraphBuilder2 graphBuilder, IBaseFilter baseFilter,
            Guid pinCategory, VideoCapability resolutionToSet, ref VideoCapability[] capabilities)
        {
            object streamConfigObject;
            graphBuilder.FindInterface(pinCategory, MediaType.Video, baseFilter, typeof(IAMStreamConfig).GUID, out streamConfigObject);

            if(streamConfigObject != null)
            {
                IAMStreamConfig streamConfig = null;

                try
                {
                    streamConfig = (IAMStreamConfig)streamConfigObject;
                }

                catch { }

                if(streamConfig != null)
                {
                    if(capabilities == null)
                    {
                        try
                        {
                            capabilities = DirectShow.VideoCapability.FromStreamConfig(streamConfig);
                        }

                        catch { }
                    }

                    if(resolutionToSet != null)
                    {
                        SetResolution(streamConfig, resolutionToSet);
                    }
                }

                Marshal.ReleaseComObject(streamConfigObject);
            }

            if(capabilities == null)
                capabilities = new VideoCapability[0];
        }



        public void ShowPropertiesWindow()
        {
            PropertiesWindow vspw = new PropertiesWindow
            {
                Owner = Application.Current.MainWindow,
                DataContext = PropertiesModel
            };

            bool videoIsEnabled = Grabber.VideoStreamEnable;

            if (!Grabber.VideoStreamEnable)
                Grabber.VideoStreamEnable = true;

            Grabber.NewVideoImageEvent += (WriteableBitmap image) => PropertiesModel.Frame = image;
            vspw.ShowDialog();
            Grabber.NewVideoImageEvent -= (WriteableBitmap image) => PropertiesModel.Frame = image;

            Grabber.VideoStreamEnable = videoIsEnabled;
        }



        private VideoInput GetCurrentCrossbarInput(IAMCrossbar crossbar)
        {
            VideoInput videoInput = VideoInput.Default;
            int inPinsCount, outPinsCount;

            if(crossbar.get_PinCounts(out outPinsCount, out inPinsCount) == 0)
            {
                int videoOutputPinIndex = -1;
                int pinIndexRelated;
                PhysicalConnectorType type;

                for(int i = 0; i < outPinsCount; i++)
                {
                    if(crossbar.get_CrossbarPinInfo(false, i, out pinIndexRelated, out type) != 0)
                        continue;

                    if(type == PhysicalConnectorType.VideoDecoder)
                    {
                        videoOutputPinIndex = i;
                        break;
                    }
                }

                if(videoOutputPinIndex != -1)
                {
                    int videoInputPinIndex;

                    if(crossbar.get_IsRoutedTo(videoOutputPinIndex, out videoInputPinIndex) == 0)
                    {
                        PhysicalConnectorType inputType;

                        crossbar.get_CrossbarPinInfo(true, videoInputPinIndex, out pinIndexRelated, out inputType);

                        videoInput = new VideoInput(videoInputPinIndex, inputType);
                    }
                }
            }

            return videoInput;
        }



        private void SetCurrentCrossbarInput(IAMCrossbar crossbar, VideoInput videoInput)
        {
            int outPinsCount, inPinsCount, _;

            if(videoInput._type != PhysicalConnectorType.Default)
            {
                if(crossbar.get_PinCounts(out outPinsCount, out inPinsCount) == 0)
                {
                    int videoOutputPinIndex = -1;
                    int videoInputPinIndex = -1;
                    PhysicalConnectorType type;

                    for(int i = 0; i < outPinsCount; i++)
                    {
                        if(crossbar.get_CrossbarPinInfo(false, i, out _, out type) != 0)
                            continue;

                        if(type == PhysicalConnectorType.VideoDecoder)
                        {
                            videoOutputPinIndex = i;
                            break;
                        }
                    }

                    for(int i = 0; i < inPinsCount; i++)
                    {
                        if(crossbar.get_CrossbarPinInfo(true, i, out _, out type) != 0)
                            continue;

                        if((type == videoInput._type) && (i == videoInput._index))
                        {
                            videoInputPinIndex = i;
                            break;
                        }
                    }

                    if((videoInputPinIndex != -1) && (videoOutputPinIndex != -1) && (crossbar.CanRoute(videoOutputPinIndex, videoInputPinIndex) == 0))
                        crossbar.Route(videoOutputPinIndex, videoInputPinIndex);
                }
            }
        }

        public bool SetCameraProperty(CameraControlProperties property, int value, ControlFlags controlFlags)
        {
            bool ret = true;

            if ((deviceMoniker == null) || (string.IsNullOrEmpty(deviceMoniker)))
                throw new ArgumentException("Video source is not specified.");

            lock (sync)
            {
                object tempSourceObject = null;

                try
                {
                    tempSourceObject = FilterInfo.CreateFilter(deviceMoniker);
                }

                catch
                {
                    throw new ApplicationException("Failed creating device object for moniker.");
                }

                if (!(tempSourceObject is IAMCameraControl))
                    throw new NotSupportedException("The video source does not support camera control.");

                IAMCameraControl pCamControl = (IAMCameraControl)tempSourceObject;
                int hr = pCamControl.Set(property, value, controlFlags);

                ret = (hr >= 0);

                Marshal.ReleaseComObject(tempSourceObject);
            }

            return ret;
        }

        public bool GetCameraProperty(CameraControlProperties property, out int value, out ControlFlags controlFlags)
        {
            bool ret = true;

            if ((deviceMoniker == null) || (string.IsNullOrEmpty(deviceMoniker)))
                throw new ArgumentException("Video source is not specified.");

            lock (sync)
            {
                object tempSourceObject = null;

                try
                {
                    tempSourceObject = FilterInfo.CreateFilter(deviceMoniker);
                }

                catch
                {
                    throw new ApplicationException("Failed creating device object for moniker.");
                }

                if (!(tempSourceObject is IAMCameraControl))
                    throw new NotSupportedException("The video source does not support camera control.");

                IAMCameraControl pCamControl = (IAMCameraControl)tempSourceObject;
                int hr = pCamControl.Get(property, out value, out controlFlags);

                ret = (hr >= 0);

                Marshal.ReleaseComObject(tempSourceObject);
            }

            return ret;
        }

        public bool GetCameraPropertyRange(CameraControlProperties property, out int minValue, out int maxValue, out int stepSize, out int defaultValue, out ControlFlags controlFlags)
        {
            bool ret = true;

            if ((deviceMoniker == null) || (string.IsNullOrEmpty(deviceMoniker)))
                throw new ArgumentException("Video source is not specified.");

            lock (sync)
            {
                object tempSourceObject = null;

                try
                {
                    tempSourceObject = FilterInfo.CreateFilter(deviceMoniker);
                }

                catch
                {
                    throw new ApplicationException("Failed creating device object for moniker.");
                }

                if (!(tempSourceObject is IAMCameraControl))
                    throw new NotSupportedException("The video source does not support camera control.");

                IAMCameraControl pCamControl = (IAMCameraControl)tempSourceObject;
                int hr = pCamControl.GetRange(property, out minValue, out maxValue, out stepSize, out defaultValue, out controlFlags);

                ret = (hr >= 0);

                Marshal.ReleaseComObject(tempSourceObject);
            }

            return ret;
        }

        public bool SetVideoProperty(VideoProcAmpProperties property, int value, ControlFlags controlFlags)
        {
            bool ret = true;

            if ((deviceMoniker == null) || (string.IsNullOrEmpty(deviceMoniker)))
            {
                throw new ArgumentException("Video source is not specified.");
            }

            lock (sync)
            {
                object tempSourceObject = null;

                try
                {
                    tempSourceObject = FilterInfo.CreateFilter(deviceMoniker);
                }

                catch
                {
                    throw new ApplicationException("Failed creating device object for moniker.");
                }

                if (!(tempSourceObject is IAMVideoProcAmp))
                    throw new NotSupportedException("The video source does not support camera control.");

                IAMVideoProcAmp pCamControl = (IAMVideoProcAmp)tempSourceObject;
                int hr = pCamControl.Set(property, value, controlFlags);

                ret = (hr >= 0);

                Marshal.ReleaseComObject(tempSourceObject);
            }

            return ret;
        }

        public bool GetVideoProperty(VideoProcAmpProperties property, out int value, out ControlFlags controlFlags)
        {
            bool ret = true;

            // check if source was set
            if ((deviceMoniker == null) || (string.IsNullOrEmpty(deviceMoniker)))
            {
                throw new ArgumentException("Video source is not specified.");
            }

            lock (sync)
            {
                object tempSourceObject = null;

                // create source device's object
                try
                {
                    tempSourceObject = FilterInfo.CreateFilter(deviceMoniker);
                }
                catch
                {
                    throw new ApplicationException("Failed creating device object for moniker.");
                }

                if (!(tempSourceObject is IAMVideoProcAmp))
                    throw new NotSupportedException("The video source does not support camera control.");

                IAMVideoProcAmp pCamControl = (IAMVideoProcAmp)tempSourceObject;
                int hr = pCamControl.Get(property, out value, out controlFlags);

                ret = (hr >= 0);

                Marshal.ReleaseComObject(tempSourceObject);
            }

            return ret;
        }

        public bool GetVideoPropertyRange(VideoProcAmpProperties property, out int minValue, out int maxValue, out int stepSize, out int defaultValue, out ControlFlags controlFlags)
        {
            bool ret = true;

            if ((deviceMoniker == null) || (string.IsNullOrEmpty(deviceMoniker)))
            {
                throw new ArgumentException("Video source is not specified.");
            }

            lock (sync)
            {
                object tempSourceObject = null;

                try
                {
                    tempSourceObject = FilterInfo.CreateFilter(deviceMoniker);
                }

                catch
                {
                    throw new ApplicationException("Failed creating device object for moniker.");
                }

                if (!(tempSourceObject is IAMVideoProcAmp))
                    throw new NotSupportedException("The video source does not support camera control.");

                IAMVideoProcAmp pCamControl = (IAMVideoProcAmp)tempSourceObject;
                int hr = pCamControl.GetRange(property, out minValue, out maxValue, out stepSize, out defaultValue, out controlFlags);

                ret = (hr >= 0);

                Marshal.ReleaseComObject(tempSourceObject);
            }

            return ret;
        }

    }
}
