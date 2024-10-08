﻿using ImageProcessLib.OpenCL.Compute.Bindings;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;


namespace ImageProcessLib.OpenCL.Compute
{
    /// <summary>
    /// Represents a list of OpenCL generated or user created events.
    /// </summary>
    /// <seealso cref="ComputeCommandQueue"/>
    public class ComputeEventList : IList<ComputeEventBase>
    {
        #region Fields

        [DebuggerBrowsable(DebuggerBrowsableState.RootHidden)]
        private readonly List<ComputeEventBase> _events;

        #endregion

        #region Constructors

        /// <summary>
        /// Creates an empty <see cref="ComputeEventList"/>.
        /// </summary>
        public ComputeEventList()
        {
            _events = new List<ComputeEventBase>();
        }

        /// <summary>
        /// Creates a new <see cref="ComputeEventList"/> from an existing list of <see cref="ComputeEventBase"/>s.
        /// </summary>
        /// <param name="events"> A list of <see cref="ComputeEventBase"/>s. </param>
        public ComputeEventList(IList<ComputeEventBase> events)
        {
            _events = new List<ComputeEventBase>(events);
        }

        #endregion

        #region Properties

        /// <summary>
        /// Gets the last <see cref="ComputeEventBase"/> on the list.
        /// </summary>
        /// <value> The last <see cref="ComputeEventBase"/> on the list. </value>
        public ComputeEventBase Last => _events[_events.Count - 1];

        #endregion

        #region Public methods

        /// <summary>
        /// Waits on the host thread for the specified events to complete.
        /// </summary>
        /// <param name="events"> The events to be waited for completition. </param>
        public static void Wait(ICollection<ComputeEventBase> events)
        {
            CLEventHandle[] eventHandles = ComputeTools.ExtractHandles(events, out var eventWaitListSize);
            ComputeErrorCode error = CL12.WaitForEvents(eventWaitListSize, eventHandles);
            ComputeException.ThrowOnError(error);
        }

        /// <summary>
        /// Waits on the host thread for the <see cref="ComputeEventBase"/>s in the <see cref="ComputeEventList"/> to complete.
        /// </summary>
        public void Wait()
        {
            Wait(_events);
        }

        #endregion

        #region IList<ComputeEventBase> Members

        /// <summary>
        /// 
        /// </summary>
        /// <param name="item"></param>
        /// <returns></returns>
        public int IndexOf(ComputeEventBase item)
        {
            return _events.IndexOf(item);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="index"></param>
        /// <param name="item"></param>
        public void Insert(int index, ComputeEventBase item)
        {
            _events.Insert(index, item);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="index"></param>
        public void RemoveAt(int index)
        {
            _events.RemoveAt(index);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="index"></param>
        /// <returns></returns>
        public ComputeEventBase this[int index]
        {
            get => _events[index];
            set => _events[index] = value;
        }

        #endregion

        #region ICollection<ComputeEventBase> Members

        /// <summary>
        /// 
        /// </summary>
        /// <param name="item"></param>
        public void Add(ComputeEventBase item)
        {
            _events.Add(item);
        }

        /// <summary>
        /// 
        /// </summary>
        public void Clear()
        {
            _events.Clear();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="item"></param>
        /// <returns></returns>
        public bool Contains(ComputeEventBase item)
        {
            return _events.Contains(item);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="array"></param>
        /// <param name="arrayIndex"></param>
        public void CopyTo(ComputeEventBase[] array, int arrayIndex)
        {
            _events.CopyTo(array, arrayIndex);
        }

        /// <summary>
        /// 
        /// </summary>
        public int Count => _events.Count;

        /// <summary>
        /// 
        /// </summary>
        public bool IsReadOnly => false;

        /// <summary>
        /// 
        /// </summary>
        /// <param name="item"></param>
        /// <returns></returns>
        public bool Remove(ComputeEventBase item)
        {
            return _events.Remove(item);
        }

        #endregion

        #region IEnumerable<ComputeEventBase> Members

        /// <summary>
        /// 
        /// </summary>
        /// <returns></returns>
        public IEnumerator<ComputeEventBase> GetEnumerator()
        {
            return ((IEnumerable<ComputeEventBase>)_events).GetEnumerator();
        }

        #endregion

        #region IEnumerable Members

        IEnumerator IEnumerable.GetEnumerator()
        {
            return ((IEnumerable)_events).GetEnumerator();
        }

        #endregion
    }
}