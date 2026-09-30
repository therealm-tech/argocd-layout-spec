{{/*
Deep-merges .src into .dst in place. Maps merge recursively, anything else is
replaced, and a null removes the key (SPEC §6.2). Named templates can only
return strings, hence the mutation.
*/}}
{{- define "layout.merge" -}}
{{- $dst := .dst -}}
{{- range $k, $v := .src -}}
{{- if kindIs "invalid" $v -}}
{{- $_ := unset $dst $k -}}
{{- else if kindIs "map" $v -}}
{{- if not (kindIs "map" (index $dst $k)) -}}
{{- $_ := set $dst $k (dict) -}}
{{- end -}}
{{- include "layout.merge" (dict "dst" (index $dst $k) "src" $v) -}}
{{- else -}}
{{- $_ := set $dst $k $v -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Where the catalog comes from, as JSON: the `catalog` chart dependency when
there is one, the catalog/ directory otherwise. A catalog dependency names its
Git repository in `sources`, its directory there in the `layout/catalog-path`
annotation (the root by default), and is tagged v<chart version>.
*/}}
{{- define "layout.catalog" -}}
{{- $subcharts := .Subcharts | default (dict) -}}
{{- if hasKey $subcharts "catalog" -}}
{{- $chart := (index $subcharts "catalog").Chart -}}
{{- if not $chart.Sources -}}
{{- fail "the catalog chart must name its Git repository in `sources`" -}}
{{- end -}}
{{- $path := index ($chart.Annotations | default (dict)) "layout/catalog-path" | default "" | trimSuffix "/" -}}
{{- dict "remote" true "repoURL" (first $chart.Sources) "path" $path "revision" (printf "v%s" $chart.Version) | toJson -}}
{{- else -}}
{{- dict "remote" false | toJson -}}
{{- end -}}
{{- end -}}

{{/* The content of layout file .path, empty when it does not exist. */}}
{{- define "layout.read" -}}
{{- if and .catalog.remote (hasPrefix "catalog/" .path) -}}
{{- (index .root.Subcharts "catalog").Files.Get (trimPrefix "catalog/" .path) -}}
{{- else -}}
{{- .root.Files.Get .path -}}
{{- end -}}
{{- end -}}

{{/* "true" when layout directory .path holds any file, empty otherwise. */}}
{{- define "layout.exists" -}}
{{- $files := .root.Files -}}
{{- $path := .path -}}
{{- if and .catalog.remote (hasPrefix "catalog/" .path) -}}
{{- $files = (index .root.Subcharts "catalog").Files -}}
{{- $path = trimPrefix "catalog/" .path -}}
{{- end -}}
{{- if gt (len ($files.Glob (printf "%s/**" $path))) 0 -}}
true
{{- end -}}
{{- end -}}

{{/* Merges every existing file of .paths, in order, into .dst. */}}
{{- define "layout.mergeFiles" -}}
{{- $ctx := . -}}
{{- range $path := .paths -}}
{{- $content := include "layout.read" (dict "root" $ctx.root "catalog" $ctx.catalog "path" $path) | fromYaml -}}
{{- if hasKey $content "Error" -}}
{{- fail (printf "%s: %s" $path $content.Error) -}}
{{- end -}}
{{- include "layout.merge" (dict "dst" $ctx.dst "src" $content) -}}
{{- end -}}
{{- end -}}

{{/* Fails the render when property .name is undefined (SPEC §9.2.3). */}}
{{- define "layout.requireProperty" -}}
{{- if not (hasKey .props .name) -}}
{{- fail (printf "%s: undefined property %q" .context .name) -}}
{{- end -}}
{{- end -}}

{{/* A Kustomize patch target from a resource identity (SPEC §2). */}}
{{- define "layout.target" -}}
{{- $parts := splitList "/" .identity -}}
{{- if ne (len $parts) 3 -}}
{{- fail (printf "%s: malformed resource identity %q" .context .identity) -}}
{{- end -}}
{{- $nameParts := splitList "_" (index $parts 2) -}}
{{- if ne (index $parts 0) "core" }}
group: {{ index $parts 0 }}
{{- end }}
kind: {{ index $parts 1 }}
name: {{ index $nameParts 0 }}
{{- if gt (len $nameParts) 1 }}
namespace: {{ index $nameParts 1 }}
{{- end }}
{{- end -}}

{{/*
Kustomize patches setting mapped properties (SPEC §9.3): one JSON patch per
resource, one `add` per pointer.
*/}}
{{- define "layout.patches" -}}
{{- $ctx := . -}}
{{- range $identity, $pointers := .mapping }}
- target:
    {{- include "layout.target" (dict "identity" $identity "context" $ctx.context) | trim | nindent 4 }}
  patch: |-
    {{- range $pointer, $property := $pointers }}
    - op: add
      path: {{ $pointer }}
      {{- include "layout.requireProperty" (dict "props" $ctx.props "name" $property "context" $ctx.context) }}
      value: {{ index $ctx.props $property | toJson }}
    {{- end }}
{{- end }}
{{- end -}}

{{/* The repository path of a file of the layout. */}}
{{- define "layout.repoPath" -}}
{{- $base := .root.Values.layout.path | default "." -}}
{{- if eq $base "." -}}
{{- .path -}}
{{- else -}}
{{- printf "%s/%s" (trimSuffix "/" $base) .path -}}
{{- end -}}
{{- end -}}

{{/* A values file as the Application reaches it, through its `ref` source. */}}
{{- define "layout.valuesRef" -}}
{{- if and .catalog.remote (hasPrefix "catalog/" .path) -}}
{{- printf "$catalog/%s" (include "layout.catalogPath" (dict "catalog" .catalog "path" .path)) -}}
{{- else -}}
{{- printf "$layout/%s" (include "layout.repoPath" .) -}}
{{- end -}}
{{- end -}}

{{/*
The manifests of layer .layer as a Kustomize component of base/: a path
relative to it, or a remote URL for a catalog in its own repository.
*/}}
{{- define "layout.component" -}}
{{- if and .catalog.remote (hasPrefix "catalog/" .layer) -}}
{{- printf "%s//%s/manifests?ref=%s" .catalog.repoURL (include "layout.catalogPath" (dict "catalog" .catalog "path" .layer)) .catalog.revision -}}
{{- else -}}
{{- printf "../%s/manifests" .layer -}}
{{- end -}}
{{- end -}}

{{/* The path of catalog file .path in the catalog's own repository. */}}
{{- define "layout.catalogPath" -}}
{{- $rel := trimPrefix "catalog/" .path -}}
{{- if .catalog.path -}}
{{- printf "%s/%s" .catalog.path $rel -}}
{{- else -}}
{{- $rel -}}
{{- end -}}
{{- end -}}
