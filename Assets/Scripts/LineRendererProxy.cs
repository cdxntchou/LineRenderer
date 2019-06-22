using System.Collections;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using UnityEngine;
using UnityEngine.Rendering;

[ExecuteInEditMode]
public class LineRendererProxy : MonoBehaviour
{
//    private Mesh theMesh;

    [SerializeField]
    public Material theMaterial;

    private List<Matrix4x4> matrices;
    private MaterialPropertyBlock properties;

    // per instance properties (TODO: move as much to shaders as possible)
    private Vector4[] coordX;
    private Vector4[] coordY;
    private Vector4[] Fx;
    private Vector4[] Fy;
    private Vector4[] Gx;
    private Vector4[] Gy;
    private Vector4[] halfPixel;
    private Vector4[] lineClamp;

    private Vector4 positionTransform;

    public bool forceRebuild;
    private Bounds lineBounds;
    private ComputeBuffer lineBuffer;
    private int lineCount;

    public struct Line
    {
        public Vector3 v0;
        public Vector3 v1;
        public Vector3 color;
    }

    void AddLine(int v0, int v1, Mesh mesh, List<Line> lines, HashSet<int> vertPairs)
    {
        // no degenerates
        if (v1 == v0)
            return;

        // sort
        if (v1 < v0)
        {
            int temp = v0;
            v0 = v1;
            v1 = temp;
        }

        // check if already exists
        int combinedIndex = (v0 * 65536 + v1);
        if (vertPairs.Contains(combinedIndex))
            return;
        else
            vertPairs.Add(combinedIndex);

        // add line to list
        lines.Add(
            new Line()
            {
                v0 = mesh.vertices[v0],
                v1 = mesh.vertices[v1],
                color = new Vector3(Random.value, Random.value, Random.value),
            });
    }

    void BuildLineBuffer(Mesh mesh)
    {
        HashSet<int> vertPairs = new HashSet<int>();
        List<Line> lines = new List<Line>();
        for (int i = 0; i < mesh.triangles.Length; i += 3)
        {
            int v0 = mesh.triangles[i + 0];
            int v1 = mesh.triangles[i + 1];
            int v2 = mesh.triangles[i + 2];
            AddLine(v0, v1, mesh, lines, vertPairs);
            AddLine(v1, v2, mesh, lines, vertPairs);
            AddLine(v2, v0, mesh, lines, vertPairs);
        }

        lineCount = lines.Count;
        lineBuffer = new ComputeBuffer(lineCount, Marshal.SizeOf(typeof(Line)), ComputeBufferType.Default);
        lineBuffer.SetData(lines);

        lineBounds = mesh.bounds;
    }

    // Start is called before the first frame update
    void Start()
    {
    }

    void DrawLineTest(
        int lineIndex,
        Vector2 p0_t0,          // pixel coordinates        // TODO: 3d coords!
        Vector2 p1_t0,          // pixel coordinates
        Vector2 p0_t1,          // pixel coordinates
        Vector2 p1_t1,          // pixel coordinates
        float line_width,       // pixels
        float aa_width)         // pixels
    {
        // find orthogonal transform:  F(p).x=	p.x * Fx.x + p.y * Fx.y + Fx.z,		mapping (0,0) -> p0_t0, and (1,0) -> p1_t0
        Vector2 delta0 = p1_t0 - p0_t0;
        Vector2 delta1 = p1_t1 - p0_t1;

        Vector4 Fx, Fy;
        Fx.x = delta0.x;
        Fx.y = delta0.y;
        Fx.z = p0_t0.x;
        Fy.x = delta0.y;
        Fy.y = -delta0.x;
        Fy.z = p0_t0.y;

        Vector4 Gx, Gy;
        Gx.x = delta1.x;
        Gx.y = delta1.y;
        Gx.z = p0_t1.x;
        Gy.x = delta1.y;
        Gy.y = -delta1.x;
        Gy.z = p0_t1.y;

        // invert matrix:		mapping (p0_t0) -> (0, 0)  and (p1_t0) -> (1, 0)
        float Flength2 = Vector2.Dot(delta0, delta0);
        Vector4 FIx, FIy;
        FIx.x = Fx.x / Flength2;
        FIx.y = Fy.x / Flength2;
        FIy.x = Fx.y / Flength2;
        FIy.y = Fy.y / Flength2;
        FIx.z = (-Fx.z * FIx.x) + (-Fy.z * FIx.y);
        FIy.z = (-Fx.z * FIy.x) + (-Fy.z * FIy.y);
        FIx.w = 0.0f;
        FIy.w = 0.0f;

        float Glength2 = Vector2.Dot(delta1, delta1);
        Vector4 GIx, GIy;
        GIx.x = Gx.x / Glength2;
        GIx.y = Gy.x / Glength2;
        GIy.x = Gx.y / Glength2;
        GIy.y = Gy.y / Glength2;
        GIx.z = (-Gx.z * GIx.x) + (-Gy.z * GIx.y);
        GIy.z = (-Gx.z * GIy.x) + (-Gy.z * GIy.y);
        GIx.w = 0.0f;
        GIy.w = 0.0f;

        Vector4 half_pixel;
        float average_length = (Mathf.Sqrt(Flength2) + Mathf.Sqrt(Glength2)) * 0.5f;
        half_pixel.x = aa_width / average_length;
        half_pixel.y = aa_width / average_length;
        half_pixel.z = 0.0f;
        half_pixel.w = 0.0f;

        Vector4 line_clamp;
        line_clamp.x = 0.0f;
        line_clamp.y = 1.0f;
        line_clamp.z = -line_width / average_length;
        line_clamp.w = line_width / average_length;

        // find signed distance (in pixels) to line at time zero: (p0_t0, p1_t0)
        // L(x)=	dot(x, L')	- dot(l0, L')
        Vector2 L_perp = new Vector2(p1_t0.y - p0_t0.y, p0_t0.x - p1_t0.x);
        Vector2 L_perp_normalized = L_perp;
        L_perp_normalized.Normalize();
        
        float offset = Vector2.Dot(L_perp_normalized, p0_t0);
        Vector4 L = new Vector4(L_perp_normalized.x, L_perp_normalized.y, -offset, 0.0f);

        // build matrix rotation into L space for old and new points

        // we want to map [worldspace] -> [line space 0],	with a 2x3 matrix
        // and then [line space 0] -> [line space -1]  (previous frame)

        ////
        // ###ctchou $TODO this is not correct, because the intersection point can be arbitrarily far away, not limited by line_width
        float min_x = Mathf.Min(p0_t0.x, p0_t1.x, p1_t0.x, p1_t1.x) - line_width * 4 - aa_width;
        float min_y = Mathf.Min(p0_t0.y, p0_t1.y, p1_t0.y, p1_t1.y) - line_width * 4 - aa_width;
        float max_x = Mathf.Max(p0_t0.x, p0_t1.x, p1_t0.x, p1_t1.x) + line_width * 4 + aa_width;
        float max_y = Mathf.Max(p0_t0.y, p0_t1.y, p1_t0.y, p1_t1.y) + line_width * 4 + aa_width;

        // vertex shader constants
        {
            coordX[lineIndex] = new Vector4(min_x, min_x, max_x, max_x);
            coordY[lineIndex] = new Vector4(max_y, min_y, max_y, min_y);
        }

        // pixel shader constants
        {
            //            pConstData->m_line_distance = L;
            //		pConstData->m_point_transform=	T_inv;

            //		pConstData->m_line_params.x=	line_width;
            //		pConstData->m_line_params.y=	0.5f;
            //		pConstData->m_line_params.z=	0.0f;
            //		pConstData->m_line_params.z=	1.0f;

            this.Fx[lineIndex] = FIx;
            this.Fy[lineIndex] = FIy;
            this.Gx[lineIndex] = GIx;
            this.Gy[lineIndex] = GIy;
            this.halfPixel[lineIndex] = half_pixel;
            this.lineClamp[lineIndex] = line_clamp;

//            pConstData->m_color = D3DXVECTOR4(1.0f, 1.0f, 0.0f, 1.0f);
        }

        //        s_video::g_pd3dDevice->VSSetShader(s_shaders::get_vertex_shader(_shader_quad_vs));
        //        s_video::g_pd3dDevice->PSSetShader(s_shaders::get_pixel_shader(_shader_line_aa_ps));
    }

    // Update is called once per frame
    void Update()
    {
        if (forceRebuild)
        {
            lineBuffer = null;
            forceRebuild = false;
        }

        if (lineBuffer == null)
        {
            Mesh mesh = GetComponent<MeshFilter>().sharedMesh;
            BuildLineBuffer(mesh);
        }

        if (theMaterial != null)
        {
            theMaterial.SetBuffer("_LineBuffer", lineBuffer);
        }

        if (matrices == null)
        {
            matrices = new List<Matrix4x4>();
        }

        if (matrices.Count == 0)
        {
            matrices.Add(Matrix4x4.TRS(new Vector3(0.0f, 0.0f, 0.0f), Quaternion.identity, Vector3.one));
            matrices.Add(Matrix4x4.TRS(new Vector3(10.0f, 0.0f, 0.0f), Quaternion.identity, Vector3.one));
            matrices.Add(Matrix4x4.TRS(new Vector3(0.0f, 10.0f, 0.0f), Quaternion.identity, Vector3.one));
            matrices.Add(Matrix4x4.TRS(new Vector3(10.0f, 10.0f, 0.0f), Quaternion.identity, Vector3.one));
            matrices.Add(Matrix4x4.TRS(new Vector3(0.0f, 0.0f, 20.0f), Quaternion.identity, Vector3.one));
        }
        else
        {
            matrices[0] = Matrix4x4.TRS(
                new Vector3(Mathf.Sin(Time.time), 0.0f, 0.0f),
                Quaternion.AngleAxis(Time.time * 10.0f, new Vector3(1.0f, 0.7f, 1.2f)),
                new Vector3(2.0f, 1.0f, 1.0f));
        }

        if (properties == null)
        {
            properties = new MaterialPropertyBlock();
        }
        if (properties != null)
        {
            if ((coordX == null) || (coordX.Length != matrices.Count))
                coordX = new Vector4[matrices.Count];

            if ((coordY == null) || (coordY.Length != matrices.Count))
                coordY = new Vector4[matrices.Count];

            if ((Fx == null) || (Fx.Length != matrices.Count))
                Fx = new Vector4[matrices.Count];

            if ((Fy == null) || (Fy.Length != matrices.Count))
                Fy = new Vector4[matrices.Count];

            if ((Gx == null) || (Gx.Length != matrices.Count))
                Gx = new Vector4[matrices.Count];

            if ((Gy == null) || (Gy.Length != matrices.Count))
                Gy = new Vector4[matrices.Count];

            if ((halfPixel == null) || (halfPixel.Length != matrices.Count))
                halfPixel = new Vector4[matrices.Count];

            if ((lineClamp == null) || (lineClamp.Length != matrices.Count))
                lineClamp = new Vector4[matrices.Count];

            float line_width = 1.0f;
            float aa_width = 1.0f;
            for (int lineIndex = 0; lineIndex < matrices.Count; lineIndex++)
            {
                Vector2 p0 = new Vector2(lineIndex * lineIndex * 50.0f + lineIndex * 50.0f + 10.0f, 100.0f);
                Vector2 p1 = new Vector2(lineIndex * lineIndex * 50.0f + 10.0f, 800.0f);

                // TODO: 3d coordinates
                DrawLineTest(
                    lineIndex,
                    p0,                 // p0, t0 pixel coordinates
                    p1,                 // p1, t0 pixel coordinates
                    p0 + new Vector2(20.0f, 0.0f),                 // p0, t1 pixel coordinates
                    p1 - new Vector2(50.0f, 0.0f),                 // p1, t1 pixel coordinates
                    line_width,         // pixels
                    aa_width);          // pixels
            }

            // setup shared state
//           properties.SetVector("_PositionTransform", new Vector4(
//               2.0f / resolution.x, -2.0f / resolution.y, -1.0f, 1.0f);

            // setup instance state
            properties.SetVectorArray("_CoordX", coordX);
            properties.SetVectorArray("_CoordY", coordY);
            properties.SetVectorArray("_Fx", Fx);
            properties.SetVectorArray("_Fy", Fy);
            properties.SetVectorArray("_Gx", Gx);
            properties.SetVectorArray("_Gy", Gy);
            properties.SetVectorArray("_HalfPixel", halfPixel);
            properties.SetVectorArray("_LineClamp", lineClamp);
        }

        // draw call
        int vertexCount = lineCount * 6;
        int instanceCount = 1;
        Camera camera = null;

        if (theMaterial != null)
        {
            Graphics.DrawProcedural(
                theMaterial, lineBounds, MeshTopology.Triangles,
                vertexCount, instanceCount,
                camera, properties,
                ShadowCastingMode.Off, false, 0);
        }
    }

    void OnWillRenderObject()
    {
        // Debug.Log(gameObject.name + " is being rendered by " + Camera.current.name + " at " + Time.time);
    }
}
