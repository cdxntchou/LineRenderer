using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

[ExecuteInEditMode]
public class LineRendererProxy : MonoBehaviour
{
    private Mesh theMesh;
    public Material theMaterial;

    private List<Matrix4x4> matrices;
    private MaterialPropertyBlock properties;

    // Start is called before the first frame update
    void Start()
    {
        
    }

    // Update is called once per frame
    void Update()
    {
        if (theMesh == null)
        {
            BuildMesh();
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

        if ((theMesh != null) && (theMaterial != null) && (matrices != null) && (matrices.Count > 0))
            Graphics.DrawMeshInstanced(theMesh, 0, theMaterial, matrices, properties, ShadowCastingMode.Off, false, 0, null, LightProbeUsage.Off);
    }

    void OnWillRenderObject()
    {
        // Debug.Log(gameObject.name + " is being rendered by " + Camera.current.name + " at " + Time.time);
    }

    void BuildMesh()
    {
        theMesh = new Mesh();

        theMesh.vertices = new Vector3[4]
        {
            new Vector3(0.0f, 0.0f, 0.0f),
            new Vector3(0.0f, 1.0f, 0.0f),
            new Vector3(1.0f, 0.0f, 0.0f),
            new Vector3(1.0f, 1.0f, 0.0f),
        };

        theMesh.uv = new Vector2[4]
        {
            new Vector2(0.0f, 0.0f),
            new Vector2(0.0f, 1.0f),
            new Vector2(1.0f, 0.0f),
            new Vector2(1.0f, 1.0f),
        };

        theMesh.triangles = new int[6]
        {
            0, 1, 2,
            3, 2, 1,
        };

        theMesh.RecalculateBounds();
    }
}
