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

    private MaterialPropertyBlock properties;

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
                color = new Vector3(1.0f, 0.5f, 0.2f),  //Random.value, Random.value, Random.value),
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

    // Update is called once per frame
    void Update()
    {
        if (forceRebuild)
        {
            if (lineBuffer != null)
                lineBuffer.Release();
            lineBuffer = null;
            forceRebuild = false;
        }

        if (lineBuffer == null)
        {
            Mesh mesh = GetComponent<MeshFilter>().sharedMesh;
            BuildLineBuffer(mesh);
        }

        if (properties == null)
        {
            properties = new MaterialPropertyBlock();
        }

        if (properties != null)
        {
            properties.SetBuffer("_LineBuffer", lineBuffer);
            properties.SetMatrix("_ObjectToWorldMatrix", transform.localToWorldMatrix);

            // TODO : should use projection matrix instead of field of view
            float verticalFOV = Camera.main.fieldOfView;
            float degreesToRadians = 180.0f / 3.1415926535f;
            float tangentSpaceHeight = Mathf.Abs(2.0f * Mathf.Tan(verticalFOV * 0.5f * degreesToRadians));
            float pixelTangentSpaceHeight = tangentSpaceHeight / Camera.main.scaledPixelHeight;
            // we assume square pixels, so pixel height ~= pixel size

            properties.SetFloat("_PixelSizeTangentSpace", pixelTangentSpaceHeight);
        }

        // setup shared state
        //           properties.SetVector("_PositionTransform", new Vector4(
        //               2.0f / resolution.x, -2.0f / resolution.y, -1.0f, 1.0f);

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

    void OnDisable()
    {
        if (lineBuffer != null)
        {
            lineBuffer.Release();
            lineBuffer = null;
        }
    }

    void OnWillRenderObject()
    {
        // Debug.Log(gameObject.name + " is being rendered by " + Camera.current.name + " at " + Time.time);
    }
}
