package away3d.loaders.parsers
{
	import away3d.animators.data.SkeletonAnimationSequence;
	import away3d.animators.data.UVAnimationFrame;
	import away3d.animators.data.UVAnimationSequence;
	import away3d.animators.skeleton.JointPose;
	import away3d.animators.skeleton.Skeleton;
	import away3d.animators.skeleton.SkeletonJoint;
	import away3d.animators.skeleton.SkeletonPose;
	import away3d.arcane;
	import away3d.containers.ObjectContainer3D;
	import away3d.core.base.Geometry;
	import away3d.core.base.SkinnedSubGeometry;
	import away3d.core.base.SubGeometry;
	import away3d.entities.Mesh;
	import away3d.library.assets.IAsset;
	import away3d.loaders.misc.ResourceDependency;
	import away3d.loaders.parsers.utils.ParserUtil;
	import away3d.materials.ColorMaterial;
	import away3d.materials.DefaultMaterialBase;
	import away3d.materials.MaterialBase;
	import away3d.materials.TextureMaterial;
	import away3d.textures.Texture2DBase;
	
	import flash.display.Sprite;
	import flash.geom.Matrix;
	import flash.geom.Matrix3D;
	import flash.net.URLRequest;
	import flash.utils.ByteArray;
	import flash.utils.Endian;
	
	use namespace arcane;
	
	/**
	 * AWDParser provides a parser for the AWD data type.
	 */
	public class AWD2Parser extends ParserBase
	{
		private var _byteData : ByteArray;
		private var _startedParsing : Boolean;
		private var _cur_block_id : uint;
		private var _blocks : Vector.<AWDBlock>;
		
		private var _version : Array;
		private var _compression : uint;
		private var _streaming : Boolean;
		
		private var _texture_users : Object = {};
		
		private var _parsed_header : Boolean;
		private var _body : ByteArray;
		
		public static const UNCOMPRESSED : uint = 0;
		public static const DEFLATE : uint = 1;
		public static const LZMA : uint = 2;
		
		
		
		public static const AWD_FIELD_INT8 : uint = 1;
		public static const AWD_FIELD_INT16 : uint = 2;
		public static const AWD_FIELD_INT32 : uint = 3;
		public static const AWD_FIELD_UINT8 : uint = 4;
		public static const AWD_FIELD_UINT16 : uint = 5;
		public static const AWD_FIELD_UINT32 : uint = 6;
		public static const AWD_FIELD_FLOAT32 : uint = 7;
		public static const AWD_FIELD_FLOAT64 : uint = 8;
		
		public static const AWD_FIELD_BOOL : uint = 21;
		public static const AWD_FIELD_COLOR : uint = 22;
		public static const AWD_FIELD_BADDR : uint = 23;
		
		public static const AWD_FIELD_STRING : uint = 31;
		public static const AWD_FIELD_BYTEARRAY : uint = 32;
		
		public static const AWD_FIELD_VECTOR2x1 : uint = 41;
		public static const AWD_FIELD_VECTOR3x1 : uint = 42;
		public static const AWD_FIELD_VECTOR4x1 : uint = 43;
		public static const AWD_FIELD_MTX3x2 : uint = 44;
		public static const AWD_FIELD_MTX3x3 : uint = 45;
		public static const AWD_FIELD_MTX4x3 : uint = 46;
		public static const AWD_FIELD_MTX4x4 : uint = 47;
		
		
		
		/**
		 * Creates a new AWDParser object.
		 * @param uri The url or id of the data or file to be parsed.
		 * @param extra The holder for extra contextual data that the parser might need.
		 */
		public function AWD2Parser()
		{
			super(ParserDataFormat.BINARY);
			
			_blocks = new Vector.<AWDBlock>;
			_blocks[0] = new AWDBlock;
			_blocks[0].data = null; // Zero address means null in AWD
			
			_version = [];
		}
		
		/**
		 * Indicates whether or not a given file extension is supported by the parser.
		 * @param extension The file extension of a potential file to be parsed.
		 * @return Whether or not the given file type is supported.
		 */
		public static function supportsType(extension : String) : Boolean
		{
			extension = extension.toLowerCase();
			return extension == "awd";
		}
		
		
		/**
		 * @inheritDoc
		 */
		override arcane function resolveDependency(resourceDependency:ResourceDependency):void
		{
			if (resourceDependency.assets.length == 1) {
				var asset : Texture2DBase = resourceDependency.assets[0] as Texture2DBase;
				if (asset) {
					var mat : TextureMaterial;
					var users : Array;
					
					// Store finished asset
					_blocks[parseInt(resourceDependency.id)].data = asset;
					
					users = _texture_users[resourceDependency.id];
					for each (mat in users) {
						mat.texture = asset;
						finalizeAsset(mat);
					}
				}
			}
		}
		
		/**
		 * @inheritDoc
		 */
		/*override arcane function resolveDependencyFailure(resourceDependency:ResourceDependency):void
		{
			// apply system default
			//BitmapMaterial(mesh.material).bitmapData = defaultBitmapData;
		}*/
		
		/**
		 * Tests whether a data block can be parsed by the parser.
		 * @param data The data block to potentially be parsed.
		 * @return Whether or not the given data is supported.
		 */
		public static function supportsData(data : *) : Boolean
		{
			var bytes : ByteArray = ParserUtil.toByteArray(data);
			
			if (bytes) {
				var magic : String;
				
				bytes.position = 0;
				magic = data.readUTFBytes(3);
				bytes.position = 0;
				
				if (magic == 'AWD')
					return true;
			}
			
			return false;
		}
		
		
		/**
		 * @inheritDoc
		 */
		protected override function proceedParsing() : Boolean
		{
			if(!_startedParsing) {
				_byteData = getByteData();
				_startedParsing = true;
			}
			
			if (!_parsed_header) {
				_byteData.endian = Endian.LITTLE_ENDIAN;
				
				//TODO: Create general-purpose parseBlockRef(requiredType) (return _blocks[addr] or throw error)
				
				// Parse header and decompress body
				parseHeader();
				switch (_compression) {
					case DEFLATE:
						_body = new ByteArray;
						_byteData.readBytes(_body, 0, _byteData.bytesAvailable);
						_body.uncompress();
						break;
					case LZMA:
						// TODO: Decompress LZMA into _body
						dieWithError('LZMA decoding not yet supported in AWD parser.');
						break;
					case UNCOMPRESSED:
						_body = _byteData;
						break;
				}
				
				_body.endian = Endian.LITTLE_ENDIAN;
				_parsed_header = true;
			}
			
			while (_body.bytesAvailable > 0 && !parsingPaused && hasTime()) {
				parseNextBlock();
			}
			
			// Return complete status
			if (_body.bytesAvailable==0) {
				return PARSING_DONE;
			}
			else return MORE_TO_PARSE;
		}
		
		private function parseHeader() : void
		{
			var flags : uint;
			var body_len : Number;
			
			// Skip magic string and parse version
			_byteData.position = 3;
			_version[0] = _byteData.readUnsignedByte();
			_version[1] = _byteData.readUnsignedByte();
			
			// Parse bit flags and compression
			flags = _byteData.readUnsignedShort();
			_streaming 	= (flags & 0x1) == 0x1;
			
			_compression = _byteData.readUnsignedByte();
			
			// Check file integrity
			body_len = _byteData.readUnsignedInt();
			if (!_streaming && body_len != _byteData.bytesAvailable) {
				dieWithError('AWD2 body length does not match header integrity field');
			}
		}
		
		private function parseNextBlock() : void
		{
			var assetData : IAsset;
			var ns : uint, type : uint, flags : uint, len : uint;
			
			_cur_block_id = _body.readUnsignedInt();
			ns = _body.readUnsignedByte();
			type = _body.readUnsignedByte();
			flags = _body.readUnsignedByte();
			len = _body.readUnsignedInt();
			
			// TODO: Remove this
			if (_body.bytesAvailable < len) {
				_body.position = _body.length;
				return;
			}
			
			switch (type) {
				case 1:
					assetData = parseMeshData(len);
					break;
				case 22:
					assetData = parseContainer(len);
					break;
				case 23:
					assetData = parseMeshInstance(len);
					break;
				case 81:
					assetData = parseMaterial(len);
					break;
				case 82:
					assetData = parseTexture(len);
					break;
				case 101:
					assetData = parseSkeleton(len);
					break;
				case 102:
					assetData = parseSkeletonPose(len);
					break;
				case 103:
					assetData = parseSkeletonAnimation(len);
					break;
				case 121:
					assetData = parseUVAnimation(len);
					break;
				default:
					//trace('Ignoring block!');
					_body.position += len;
					break;
			}
			
			// Store block reference for later use
			_blocks[_cur_block_id] = new AWDBlock();
			_blocks[_cur_block_id].data = assetData;
			_blocks[_cur_block_id].id = _cur_block_id;
		}
		
		
		
		private function parseUVAnimation(blockLength : uint) : UVAnimationSequence
		{
			// TODO: not used
			blockLength = blockLength; 
			var name : String;
			var num_frames : uint;
			var frames_parsed : uint;
			var props : AWDProperties;
			var dummy : Sprite;
			var seq : UVAnimationSequence;
			
			name = parseVarStr();
			num_frames = _body.readUnsignedShort();
			
			props = parseProperties(null);
			
			seq = new UVAnimationSequence(name);
			
			frames_parsed = 0;
			dummy = new Sprite;
			while (frames_parsed < num_frames) {
				var mtx : Matrix;
				var frame_dur : uint;
				var frame : UVAnimationFrame;
				
				// TODO: Replace this with some reliable way to decompose a 2d matrix
				mtx = parseMatrix2D();
				mtx.scale(100, 100);
				dummy.transform.matrix = mtx;
				
				frame_dur = _body.readUnsignedShort();
				
				frame = new UVAnimationFrame(dummy.x*0.01, dummy.y*0.01, dummy.scaleX/100, dummy.scaleY/100, dummy.rotation);
				seq.addFrame(frame, frame_dur);
				
				frames_parsed++;
			}
			
			// Ignore for now
			parseUserAttributes();
			
			finalizeAsset(seq, name);
			
			return seq;
		}
		
		
		private function parseMaterial(blockLength : uint) : MaterialBase
		{
			// TODO: not used
			blockLength = blockLength; 
			var name : String;
			var type : uint;
			var props : AWDProperties;
			var mat : DefaultMaterialBase;
			var attributes : Object;
			var finalize : Boolean;
			var num_methods : uint;
			var methods_parsed : uint;
			
			name = parseVarStr();
			type = _body.readUnsignedByte();
			num_methods = _body.readUnsignedByte();
			
			// Read material numerical properties
			// (1=color, 2=bitmap url, 11=alpha_blending, 12=alpha_threshold, 13=repeat)
			props = parseProperties({ 1:AWD_FIELD_INT32, 2:AWD_FIELD_BADDR, 
				11:AWD_FIELD_BOOL, 12:AWD_FIELD_FLOAT32, 13:AWD_FIELD_BOOL });
			
			methods_parsed = 0;
			while (methods_parsed < num_methods) {
				var method_type : uint;
				
				method_type = _body.readUnsignedShort();
				parseProperties(null);
				parseUserAttributes();
			}
			
			attributes = parseUserAttributes();
			
			if (type == 1) { // Color material
				var color : uint;
				
				color = props.get(1, 0xcccccc);
				mat = new ColorMaterial(color);
			}
			else if (type == 2) { // Bitmap material
				//TODO: not used
				//var bmp : BitmapData;
				var texture : Texture2DBase;
				var tex_addr : uint;
				
				tex_addr = props.get(2, 0);
				texture = _blocks[tex_addr].data;
				
				// If bitmap asset has already been loaded
				if (texture) {
					mat = new TextureMaterial(texture);
					TextureMaterial(mat).alphaBlending = props.get(11, false);
					finalize = true;
				}
				else {
					// No bitmap available yet. Material will be finalized
					// when texture finishes loading.
					mat = new TextureMaterial(null);
					if (tex_addr > 0)
						_texture_users[tex_addr.toString()].push(mat);
					
					finalize = false;
				}
			}
			
			mat.extra = attributes;
			mat.alphaThreshold = props.get(12, 0.0);
			mat.repeat = props.get(13, false);
			
			if (finalize) {
				finalizeAsset(mat, name);
			}
			
			return mat;
		}
		
		
		private function parseTexture(blockLength : uint) : Texture2DBase
		{
			// TODO: not used
			blockLength = blockLength; 
			var name : String;
			var type : uint;
			var data_len : uint;
			var asset : Texture2DBase;
			
			name = parseVarStr();
			type = _body.readUnsignedByte();
			data_len = _body.readUnsignedInt();
			
			_texture_users[_cur_block_id.toString()] = [];
			
			// External
			if (type == 0) {
				var url : String;
				
				url = _body.readUTFBytes(data_len);
				
				addDependency(_cur_block_id.toString(), new URLRequest(url));
			}
			else {
				var data : ByteArray;
				// TODO: not used
				// var loader : Loader;
				
				data = new ByteArray();
				_body.readBytes(data, 0, data_len);
				
				addDependency(_cur_block_id.toString(), null, false, data);
			}
			
			// Ignore for now
			parseProperties(null);
			parseUserAttributes();
			
			
			// TODO: Don't do this. Get texture properly
			/*
			finalizeAsset(asset, name);
			*/
			
			pauseAndRetrieveDependencies();
			
			return asset;
		}
		
		
		private function parseSkeleton(blockLength : uint) : Skeleton
		{
			// TODO: not used
			blockLength = blockLength; 
			var name : String;
			var num_joints : uint;
			var joints_parsed : uint;
			var skeleton : Skeleton;
			
			name = parseVarStr();
			num_joints = _body.readUnsignedShort();
			skeleton = new Skeleton();
			
			// Discard properties for now
			parseProperties(null);
			
			joints_parsed = 0;
			while (joints_parsed < num_joints) {
				// TODO: not used
				//	var parent_id : uint;
				// TODO: not used
				//var joint_name : String;
				var joint : SkeletonJoint;
				var ibp : Matrix3D;
				
				// Ignore joint id
				_body.readUnsignedShort();
				
				joint = new SkeletonJoint();
				joint.parentIndex = _body.readUnsignedShort() -1; // 0=null in AWD
				joint.name = parseVarStr();
				
				ibp = parseMatrix3D();
				joint.inverseBindPose = ibp.rawData;
				
				// Ignore joint props/attributes for now
				parseProperties(null);
				parseUserAttributes();
				
				skeleton.joints.push(joint);
				joints_parsed++;
			}
			
			// Discard attributes for now
			parseUserAttributes();
			
			finalizeAsset(skeleton, name);
			
			return skeleton;
		}
		
		private function parseSkeletonPose(blockLength : uint) : SkeletonPose
		{
			// TODO: not used
			blockLength = blockLength; 
			var name : String;
			var pose : SkeletonPose;
			var num_joints : uint;
			var joints_parsed : uint;
			
			name = parseVarStr();
			num_joints = _body.readUnsignedShort();
			
			// Ignore properties for now
			parseProperties(null);
			
			pose = new SkeletonPose();
			
			joints_parsed = 0;
			while (joints_parsed < num_joints) {
				var joint_pose : JointPose;
				var has_transform : uint;
				
				joint_pose = new JointPose();
				
				has_transform = _body.readUnsignedByte();
				if (has_transform == 1) {
					// TODO: not used
					// var mtx0 : Matrix3D;
					var mtx_data : Vector.<Number> = parseMatrix43RawData();
					
					var mtx : Matrix3D = new Matrix3D(mtx_data);
					joint_pose.orientation.fromMatrix(mtx);
					joint_pose.translation.copyFrom(mtx.position);
					
					pose.jointPoses[joints_parsed] = joint_pose;
				}
				
				joints_parsed++;
			}
			
			// Skip attributes for now
			parseUserAttributes();
			
			finalizeAsset(pose, name);
			
			return pose;
		}
		
		private function parseSkeletonAnimation(blockLength : uint) : SkeletonAnimationSequence
		{
			// TODO: not used
			blockLength = blockLength; 
			var name : String;
			var num_frames : uint;
			var frames_parsed : uint;
			// TODO: not used
			//var frame_rate : uint;
			var frame_dur : Number;
			var animation : SkeletonAnimationSequence;
			
			name = parseVarStr();
			animation = new SkeletonAnimationSequence(name);
			
			num_frames = _body.readUnsignedShort();
			
			// Ignore properties for now (none in spec)
			parseProperties(null);
			
			frames_parsed = 0;
			while (frames_parsed < num_frames) {
				var pose_addr : uint;
				
				//TODO: Check for null?
				pose_addr = _body.readUnsignedInt();
				frame_dur = _body.readUnsignedShort();
				animation.addFrame(_blocks[pose_addr].data as SkeletonPose, frame_dur);
				
				frames_parsed++;
			}
			
			// Ignore attributes for now
			parseUserAttributes();
			
			finalizeAsset(animation, name);
			
			return animation;
		}
		
		private function parseContainer(blockLength : uint) : ObjectContainer3D
		{
			// TODO: not used
			blockLength = blockLength; 
			var name : String;
			var par_id : uint;
			var mtx : Matrix3D;
			var ctr : ObjectContainer3D;
			var parent : ObjectContainer3D;
			
			par_id = _body.readUnsignedInt();
			mtx = parseMatrix3D();
			name = parseVarStr();
			
			ctr = new ObjectContainer3D();
			ctr.transform = mtx;
			
			parent = _blocks[par_id].data as ObjectContainer3D;
			if (parent) {
				parent.addChild(ctr);
			}
			
			parseProperties(null);
			ctr.extra = parseUserAttributes();
		
			finalizeAsset(ctr, name);
			
			return ctr;
		}
		
		private function parseMeshInstance(blockLength : uint) : Mesh
		{
			// TODO: not used
			blockLength = blockLength; 
			var name : String;
			var mesh : Mesh, geom : Geometry;
			var par_id : uint, data_id : uint;
			var mtx : Matrix3D;
			var materials : Vector.<MaterialBase>;
			var num_materials : uint;
			var materials_parsed : uint;
			var parent : ObjectContainer3D;
			
			par_id = _body.readUnsignedInt();
			mtx = parseMatrix3D();
			name = parseVarStr();
			
			data_id = _body.readUnsignedInt();
			geom = _blocks[data_id].data as Geometry;
			
			materials = new Vector.<MaterialBase>;
			num_materials = _body.readUnsignedShort();
			materials_parsed = 0;
			while (materials_parsed < num_materials) {
				var mat_id : uint;
				mat_id = _body.readUnsignedInt();
				
				materials.push(_blocks[mat_id].data);
				
				materials_parsed++;
			}
			
			mesh = new Mesh(geom);
			mesh.transform = mtx;
			
			// Add to parent if one exists
			parent = _blocks[par_id].data as ObjectContainer3D;
			if (parent) {
				parent.addChild(mesh);
			}
			
			if (materials.length >= 1 && mesh.subMeshes.length == 1) {
				mesh.material = materials[0];
			}
			else if (materials.length > 1) {
				var i : uint;
				// Assign each sub-mesh in the mesh a material from the list. If more sub-meshes
				// than materials, repeat the last material for all remaining sub-meshes.
				for (i=0; i<mesh.subMeshes.length; i++) {
					mesh.subMeshes[i].material = materials[Math.min(materials.length-1, i)];
				}
			}
			
			// Ignore for now
			parseProperties(null);
			mesh.extra = parseUserAttributes();
			
			finalizeAsset(mesh, name);
			
			return mesh;
		}
		
		
		private function parseMeshData(blockLength : uint) : Geometry
		{
			// TODO: not used
			blockLength = blockLength; 
			var name : String;
			var geom : Geometry;
			var num_subs : uint;
			var subs_parsed : uint;
			var props : AWDProperties;
			var bsm : Matrix3D;
			
			// Read name and sub count
			name = parseVarStr();
			num_subs = _body.readUnsignedShort();
			
			// Read optional properties
			props = parseProperties({ 1:AWD_FIELD_MTX4x4 }); 
			
			// TODO: not used
			// var mtx : Matrix3D;
			var bsm_data : Array = props.get(1, null);
			if (bsm_data) {
				bsm = new Matrix3D(Vector.<Number>(bsm_data));
			}
			
			geom = new Geometry();
			
			// Loop through sub meshes
			subs_parsed = 0;
			while (subs_parsed < num_subs) {
				var i : uint;
				var sm_len : uint, sm_end : uint;
				var sub_geoms : Vector.<SubGeometry>;
				var skinned_sub_geom : SkinnedSubGeometry;
				var w_indices : Vector.<Number>;
				var weights : Vector.<Number>;
				
				sm_len = _body.readUnsignedInt();
				sm_end = _body.position + sm_len;
				
				// Ignore for now
				parseProperties(null);
				
				// Loop through data streams
				while (_body.position < sm_end) {
					var idx : uint = 0;
					var str_ftype : uint;
					var str_type : uint, str_len : uint, str_end : uint;
					
					// Type, field type, length
					str_type = _body.readUnsignedByte();
					str_ftype = _body.readUnsignedByte();
					str_len = _body.readUnsignedInt();
					str_end = _body.position + str_len;
					
					var x:Number, y:Number, z:Number;
					
					if (str_type == 1) {
						var verts : Vector.<Number> = new Vector.<Number>;
						while (_body.position < str_end) {
							// TODO: Respect stream field type
							x = _body.readFloat();
							y = _body.readFloat();
							z = _body.readFloat();
							
							verts[idx++] = x;
							verts[idx++] = y;
							verts[idx++] = z;
						}
					}
					else if (str_type == 2) {
						var indices : Vector.<uint> = new Vector.<uint>;
						while (_body.position < str_end) {
							// TODO: Respect stream field type
							indices[idx++] = _body.readUnsignedShort();
						}
					}
					else if (str_type == 3) {
						var uvs : Vector.<Number> = new Vector.<Number>;
						while (_body.position < str_end) {
							// TODO: Respect stream field type
							uvs[idx++] = _body.readFloat();
						}
					}
					else if (str_type == 4) {
						var normals : Vector.<Number> = new Vector.<Number>;
						while (_body.position < str_end) {
							// TODO: Respect stream field type
							normals[idx++] = _body.readFloat();
						}
					}
					else if (str_type == 6) {
						w_indices = new Vector.<Number>;
						while (_body.position < str_end) {
							// TODO: Respect stream field type
							w_indices[idx++] = _body.readUnsignedShort()*3;
						}
					}
					else if (str_type == 7) {
						weights = new Vector.<Number>;
						while (_body.position < str_end) {
							// TODO: Respect stream field type
							weights[idx++] = _body.readFloat();
						}
					}
					else {
						_body.position = str_end;
					}
				}
				
				// Ignore sub-mesh attributes for now
				parseUserAttributes();
				
				sub_geoms = buildSubGeometries(verts, indices, uvs, normals, null, weights, w_indices);
				for (i=0; i<sub_geoms.length; i++) {
					geom.addSubGeometry(sub_geoms[i]);
					// TODO: Somehow map in-sub to out-sub indices to enable look-up
					// when creating meshes (and their material assignments.)
				}
				
				subs_parsed++;
			}
			
			parseUserAttributes();
			
			finalizeAsset(geom, name);
			
			return geom;
		}
		
		
		private function buildSubGeometry(verts : Vector.<Number>, indices : Vector.<uint>, uvs : Vector.<Number>, 
										  normals : Vector.<Number>, tangents : Vector.<Number>, 
										  weights : Vector.<Number>, jointIndices : Vector.<Number>) : SubGeometry
		{
			var sub : SubGeometry;
			
			if (weights && jointIndices) {
				// If there were weights and joint indices defined, this
				// is a skinned mesh and needs to be built from skinned
				// sub-geometries.
				sub = new SkinnedSubGeometry(weights.length / (verts.length/3));
				SkinnedSubGeometry(sub).updateJointWeightsData(weights);
				SkinnedSubGeometry(sub).updateJointIndexData(jointIndices);
			}
			else {
				sub = new SubGeometry();
			}
			
			sub.updateVertexData(verts);
			sub.updateIndexData(indices);
			if (uvs) sub.updateUVData(uvs);
			if (normals) sub.updateVertexNormalData(normals);
			if (tangents) sub.updateVertexTangentData(tangents);
			
			return sub;
		}
		
		private function buildSubGeometries(verts : Vector.<Number>, indices : Vector.<uint>, uvs : Vector.<Number>, 
											normals : Vector.<Number>, tangents : Vector.<Number>, 
											weights : Vector.<Number>, jointIndices : Vector.<Number>) : Vector.<SubGeometry>
		{
			const LIMIT : uint = 3*0xffff;
			var subs : Vector.<SubGeometry> = new Vector.<SubGeometry>();
			
			if (verts.length >= LIMIT || indices.length >= LIMIT) {
				var i : uint, len : uint, outIndex : uint;
				var splitVerts : Vector.<Number> = new Vector.<Number>();
				var splitIndices : Vector.<uint> = new Vector.<uint>();
				var splitUvs : Vector.<Number> = (uvs != null)? new Vector.<Number>() : null;
				var splitNormals : Vector.<Number> = (normals != null)? new Vector.<Number>() : null;
				var splitTangents : Vector.<Number> = (tangents != null)? new Vector.<Number>() : null;
				var splitWeights : Vector.<Number> = (weights != null)? new Vector.<Number>() : null;
				var splitJointIndices: Vector.<Number> = (jointIndices != null)? new Vector.<Number>() : null;
				
				var mappings : Vector.<int> = new Vector.<int>(verts.length/3, true);
				i = mappings.length;
				while (i-->0) 
					mappings[i] = -1;
				
				// Loop over all triangles
				outIndex = 0;
				len = indices.length;
				for (i=0; i<len; i+=3) {
					var j : uint;
					
					if (outIndex >= LIMIT) {
						subs.push(buildSubGeometry(splitVerts, splitIndices, splitUvs, splitNormals, splitTangents, splitWeights, splitJointIndices));
						splitVerts = new Vector.<Number>();
						splitIndices = new Vector.<uint>();
						splitUvs = (uvs != null)? new Vector.<Number>() : null;
						splitNormals = (normals != null)? new Vector.<Number>() : null;
						splitTangents = (tangents != null)? new Vector.<Number>() : null;
						splitWeights = (weights != null)? new Vector.<Number>() : null;
						splitJointIndices = (jointIndices != null)? new Vector.<Number>() : null;
						
						j = mappings.length;
						while (j-->0)
							mappings[j] = -1;
						
						outIndex = 0;
					}
					
					// Loop over all vertices in triangle
					for (j=0; j<3; j++) {
						var originalIndex : uint;
						var splitIndex : uint;
						
						originalIndex = indices[i+j];
						
						if (mappings[originalIndex] >= 0) {
							splitIndex = mappings[originalIndex];
						}
						else {
							var o0 : uint, o1 : uint, o2 : uint,
							s0 : uint, s1 : uint, s2 : uint;
							
							o0 = originalIndex*3 + 0;
							o1 = originalIndex*3 + 1;
							o2 = originalIndex*3 + 2;
							
							// This vertex does not yet exist in the split list and
							// needs to be copied from the long list.
							splitIndex = splitVerts.length / 3;
							s0 = splitIndex*3+0;
							s1 = splitIndex*3+1;
							s2 = splitIndex*3+2;
							
							splitVerts[s0] = verts[o0];
							splitVerts[s1] = verts[o1];
							splitVerts[s2] = verts[o2];
							
							if (uvs) {
								splitUvs[s0] = uvs[o0];
								splitUvs[s1] = uvs[o1];
								splitUvs[s2] = uvs[o2];
							}
							
							if (normals) {
								splitNormals[s0] = normals[o0];
								splitNormals[s1] = normals[o1];
								splitNormals[s2] = normals[o2];
							}
							
							if (tangents) {
								splitTangents[s0] = tangents[o0];
								splitTangents[s1] = tangents[o1];
								splitTangents[s2] = tangents[o2];
							}
							
							if (weights) {
								splitWeights[s0] = weights[o0];
								splitWeights[s1] = weights[o1];
								splitWeights[s2] = weights[o2];
							}
							
							if (jointIndices) {
								splitJointIndices[s0] = jointIndices[o0];
								splitJointIndices[s1] = jointIndices[o1];
								splitJointIndices[s2] = jointIndices[o2];
							}
							
							mappings[originalIndex] = splitIndex;
						}
						
						// Store new index, which may have come from the mapping look-up,
						// or from copying a new set of vertex data from the original vector
						splitIndices[outIndex+j] = splitIndex;
					}
					
					outIndex += 3;
				}
				
				if (splitVerts.length > 0) {
					// More was added in the last iteration of the loop.
					subs.push(buildSubGeometry(splitVerts, splitIndices, splitUvs, splitNormals, splitTangents, splitWeights, splitJointIndices));
				}
			}
			else {
				subs.push(buildSubGeometry(verts, indices, uvs, normals, tangents, weights, jointIndices));
			}
			
			return subs;
		}
		
		
		private function parseVarStr() : String
		{
			var len : uint;
			
			len = _body.readUnsignedShort();
			return _body.readUTFBytes(len);
		}
		
		
		// TODO: Improve this by having some sort of key=type dictionary
		private function parseProperties(expected : Object) : AWDProperties
		{
			var list_end : uint;
			var list_len : uint;
			var props : AWDProperties;
			
			props = new AWDProperties();
			
			list_len = _body.readUnsignedInt();
			list_end = _body.position + list_len;
			
			if (expected) {
				while (_body.position < list_end) {
					var len : uint;
					var key : uint;
					var type : uint;
					
					key = _body.readUnsignedShort();
					len = _body.readUnsignedShort();
					if (expected.hasOwnProperty(key)) {
						type = expected[key];
						props.set(key, parseAttrValue(type, len));
					}
					else {
						_body.position += len;
					}
					
				}
			}
			
			return props;
		}
		
		private function parseUserAttributes() : Object
		{
			var attributes : Object;
			var list_len : uint;
			
			list_len = _body.readUnsignedInt();
			if (list_len > 0) {
				var list_end : uint;
				
				attributes = {};
				
				list_end = _body.position + list_len;
				while (_body.position < list_end) {
					var ns_id : uint;
					var attr_key : String;
					var attr_type : uint;
					var attr_len : uint;
					var attr_val : *;
					
					// TODO: Properly tend to namespaces in attributes
					ns_id = _body.readUnsignedByte();
					attr_key = parseVarStr();
					attr_type = _body.readUnsignedByte();
					attr_len = _body.readUnsignedShort();
					
					switch (attr_type) {
						case AWD_FIELD_STRING:
							attr_val = _body.readUTFBytes(attr_len);
							break;
						default:
							attr_val = 'unimplemented attribute type '+attr_type;
							_body.position += attr_len;
							break;
					}
					
					attributes[attr_key] = attr_val;
				}
			}
			
			return attributes;
		}
		
		private function parseAttrValue(type : uint, len : uint) : *
		{
			var elem_len : uint;
			var read_func : Function;
			
			switch (type) {
				case AWD_FIELD_INT8:
					elem_len = 1;
					read_func = _body.readByte;
					break;
				case AWD_FIELD_INT16:
					elem_len = 2;
					read_func = _body.readShort;
					break;
				case AWD_FIELD_INT32:
					elem_len = 4;
					read_func = _body.readInt;
					break;
				case AWD_FIELD_BOOL:
				case AWD_FIELD_UINT8:
					elem_len = 1;
					read_func = _body.readUnsignedByte;
					break;
				case AWD_FIELD_UINT16:
					elem_len = 2;
					read_func = _body.readUnsignedShort;
					break;
				case AWD_FIELD_UINT32:
				case AWD_FIELD_BADDR:
					elem_len = 4;
					read_func = _body.readUnsignedInt;
					break;
				case AWD_FIELD_FLOAT32:
					elem_len = 4;
					read_func = _body.readFloat;
					break;
				case AWD_FIELD_FLOAT64:
					elem_len = 8;
					read_func = _body.readDouble;
					break;
				case AWD_FIELD_VECTOR2x1:
				case AWD_FIELD_VECTOR3x1:
				case AWD_FIELD_VECTOR4x1:
				case AWD_FIELD_MTX3x2:
				case AWD_FIELD_MTX3x3:
				case AWD_FIELD_MTX4x3:
				case AWD_FIELD_MTX4x4:
					elem_len = 8;
					read_func = _body.readDouble;
					break;
			}
			
			if (elem_len < len) {
				var list : Array;
				var num_read : uint;
				var num_elems : uint;
				
				list = [];
				num_read = 0;
				num_elems = len / elem_len;
				while (num_read < num_elems) {
					list.push(read_func());
					num_read++;
				}
				
				return list;
			}
			else {
				var val : *;
				
				val = read_func();
				return val;
			}
		}
		
		private function parseMatrix2D() : Matrix
		{
			var mtx : Matrix;
			var mtx_raw : Vector.<Number> = parseMatrix32RawData();
			
			mtx = new Matrix(mtx_raw[0], mtx_raw[1], mtx_raw[2], mtx_raw[3], mtx_raw[4], mtx_raw[5]);
			return mtx;
		}
		
		private function parseMatrix3D() : Matrix3D
		{
			return new Matrix3D(parseMatrix43RawData());
		}
		
		
		private function parseMatrix32RawData() : Vector.<Number>
		{
			var i : uint;
			var mtx_raw : Vector.<Number> = new Vector.<Number>(6, true);
			for (i=0; i<6; i++)
				mtx_raw[i] = _body.readFloat();
			
			return mtx_raw;
		}
		
		private function parseMatrix43RawData() : Vector.<Number>
		{
			var i : uint;
			var mtx_raw : Vector.<Number> = new Vector.<Number>(16, true);
			
			mtx_raw[0] = _body.readFloat();
			mtx_raw[1] = _body.readFloat();
			mtx_raw[2] = _body.readFloat();
			mtx_raw[3] = 0.0;
			mtx_raw[4] = _body.readFloat();
			mtx_raw[5] = _body.readFloat();
			mtx_raw[6] = _body.readFloat();
			mtx_raw[7] = 0.0;
			mtx_raw[8] = _body.readFloat();
			mtx_raw[9] = _body.readFloat();
			mtx_raw[10] = _body.readFloat();
			mtx_raw[11] = 0.0;
			mtx_raw[12] = _body.readFloat();
			mtx_raw[13] = _body.readFloat();
			mtx_raw[14] = _body.readFloat();
			mtx_raw[15] = 1.0;
			
			return mtx_raw;
		}
	}
}


internal class AWDBlock
{
	public var id : uint;
	public var data : *;
}

internal dynamic class AWDProperties
{
	public function set(key : uint, value : *) : void
	{
		this[key.toString()] = value;
	}
	
	public function get(key : uint, fallback : *) : *
	{
		if (this.hasOwnProperty(key.toString()))
			return this[key.toString()];
		else return fallback;
	}
}

