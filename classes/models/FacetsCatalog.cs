﻿using System.Collections.Generic;

namespace Proviso.Models
{
    public class FacetsCatalog
    {
        private Dictionary<string, Facet> _facets = new Dictionary<string, Facet>();
        private Dictionary<string, string> _facetsByFileName = new Dictionary<string, string>();

        public int FacetCount => this._facets.Count;

        private FacetsCatalog() { }

        public static FacetsCatalog Instance => new FacetsCatalog();

        public void AddFacet(Facet added)
        {
            this._facets.Add(added.Name, added);
            this._facetsByFileName.Add(added.FileName, added.Name);
        }

        public Facet GetFacet(string facetName)
        {
            if (this._facets.ContainsKey(facetName))
                return this._facets[facetName];

            return null;
        }

        public Facet GetFacetByFileName(string filename)
        {
            if (this._facetsByFileName.ContainsKey(filename))
            {
                string facetName = this._facetsByFileName[filename];

                if (this._facets.ContainsKey(facetName))
                {
                    return this._facets[facetName];
                }
            }

            return null;
        }
    }
}