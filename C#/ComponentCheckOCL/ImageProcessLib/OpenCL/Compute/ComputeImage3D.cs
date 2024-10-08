﻿using ImageProcessLib.OpenCL.Compute.Bindings;


namespace ImageProcessLib.OpenCL.Compute
{
    using System;
    using System.Collections.Generic;

    /// <summary>
    /// Represents an OpenCL 3D image.
    /// </summary>
    /// <seealso cref="ComputeImage"/>
    public class ComputeImage3D : ComputeImage
    {
        #region Constructors

        /// <summary>
        /// Creates a new <see cref="ComputeImage3D"/>.
        /// </summary>
        /// <param name="context"> A valid <see cref="ComputeContext"/> in which the <see cref="ComputeImage3D"/> is created. </param>
        /// <param name="flags"> A bit-field that is used to specify allocation and usage information about the <see cref="ComputeImage3D"/>. </param>
        /// <param name="format"> A structure that describes the format properties of the <see cref="ComputeImage3D"/>. </param>
        /// <param name="width"> The width of the <see cref="ComputeImage3D"/> in pixels. </param>
        /// <param name="height"> The height of the <see cref="ComputeImage3D"/> in pixels. </param>
        /// <param name="depth"> The depth of the <see cref="ComputeImage3D"/> in pixels. </param>
        /// <param name="rowPitch"> The size in bytes of each row of elements of the <see cref="ComputeImage3D"/>. If <paramref name="rowPitch"/> is zero, OpenCL will compute the proper value based on <see cref="ComputeImage.Width"/> and <see cref="ComputeImage.ElementSize"/>. </param>
        /// <param name="slicePitch"> The size in bytes of each 2D slice in the <see cref="ComputeImage3D"/>. If <paramref name="slicePitch"/> is zero, OpenCL will compute the proper value based on <see cref="ComputeImage.RowPitch"/> and <see cref="ComputeImage.Height"/>. </param>
        /// <param name="data"> The data to initialize the <see cref="ComputeImage3D"/>. Can be <c>IntPtr.Zero</c>. </param>
        [Obsolete("Deprecated in OpenCL 1.2.")]
        public ComputeImage3D(ComputeContext context, ComputeMemoryFlags flags, ComputeImageFormat format, int width, int height, int depth, long rowPitch, long slicePitch, IntPtr data)
            : base(context, flags)
        {
            Handle = CL12.CreateImage3D(context.Handle, flags, ref format, new IntPtr(width), new IntPtr(height), new IntPtr(depth), new IntPtr(rowPitch), new IntPtr(slicePitch), data, out var error);
            ComputeException.ThrowOnError(error);

            Init();
        }

        private ComputeImage3D(CLMemoryHandle handle, ComputeContext context, ComputeMemoryFlags flags)
            : base(context, flags)
        {
            Handle = handle;

            Init();
        }

        #endregion

        #region Public methods

        /// <summary>
        /// Creates a new <see cref="ComputeImage3D"/> from an OpenGL 3D texture object.
        /// </summary>
        /// <param name="context"> A <see cref="ComputeContext"/> with enabled CL/GL sharing. </param>
        /// <param name="flags"> A bit-field that is used to specify usage information about the <see cref="ComputeImage3D"/>. Only <c>ComputeMemoryFlags.ReadOnly</c>, <c>ComputeMemoryFlags.WriteOnly</c> and <c>ComputeMemoryFlags.ReadWrite</c> are allowed. </param>
        /// <param name="textureTarget"> The image type of texture. Must be GL_TEXTURE_3D. </param>
        /// <param name="mipLevel"> The mipmap level of the OpenGL 2D texture object to be used. </param>
        /// <param name="textureId"> The OpenGL 2D texture object id to use. </param>
        /// <returns> The created <see cref="ComputeImage2D"/>. </returns>
        [Obsolete("Deprecated in OpenCL 1.2.")]
        public static ComputeImage3D CreateFromGLTexture3D(ComputeContext context, ComputeMemoryFlags flags, int textureTarget, int mipLevel, int textureId)
        {
            var image = CL12.CreateFromGLTexture3D(context.Handle, flags, textureTarget, mipLevel, textureId, out var error);
            ComputeException.ThrowOnError(error);

            return new ComputeImage3D(image, context, flags);
        }

        /// <summary>
        /// Gets a collection of supported <see cref="ComputeImage3D"/> <see cref="ComputeImageFormat"/>s in a <see cref="ComputeContext"/>.
        /// </summary>
        /// <param name="context"> The <see cref="ComputeContext"/> for which the collection of <see cref="ComputeImageFormat"/>s is queried. </param>
        /// <param name="flags"> The <c>ComputeMemoryFlags</c> for which the collection of <see cref="ComputeImageFormat"/>s is queried. </param>
        /// <returns> The collection of the required <see cref="ComputeImageFormat"/>s. </returns>
        public static ICollection<ComputeImageFormat> GetSupportedFormats(ComputeContext context, ComputeMemoryFlags flags)
        {
            return GetSupportedFormats(context, flags, ComputeMemoryType.Image3D);
        }

        #endregion
    }
}