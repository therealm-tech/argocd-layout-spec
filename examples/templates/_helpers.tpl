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
{{- if .Files.Glob "catalog/**" -}}
{{- fail "the catalog is both a chart dependency and a catalog/ directory: keep one" -}}
{{- end -}}
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

{{/* The files under layout directory .path, as a JSON list of layout paths. */}}
{{- define "layout.glob" -}}
{{- $files := .root.Files -}}
{{- $path := .path -}}
{{- $prefix := "" -}}
{{- if and .catalog.remote (hasPrefix "catalog/" .path) -}}
{{- $files = (index .root.Subcharts "catalog").Files -}}
{{- $path = trimPrefix "catalog/" .path -}}
{{- $prefix = "catalog/" -}}
{{- end -}}
{{- $out := list -}}
{{- range $file, $_ := $files.Glob (printf "%s/**" $path) -}}
{{- $out = append $out (printf "%s%s" $prefix $file) -}}
{{- end -}}
{{- toJson $out -}}
{{- end -}}

{{/* "true" when layout directory .path holds any file, empty otherwise. */}}
{{- define "layout.exists" -}}
{{- if include "layout.glob" . | fromJsonArray -}}
true
{{- end -}}
{{- end -}}

{{/* Layout file .path parsed as YAML, as JSON; an empty map when it does not exist. */}}
{{- define "layout.parse" -}}
{{- /* fromYaml reports a parse error as a map holding only `Error`, which a
   file may legitimately hold too: a probe key added to the content tells the
   two apart. */ -}}
{{- $content := printf "%s\n__layout_probe__: true\n" (include "layout.read" .) | fromYaml -}}
{{- if not (hasKey $content "__layout_probe__") -}}
{{- fail (printf "%s: %s" .path $content.Error) -}}
{{- end -}}
{{- toJson (omit $content "__layout_probe__") -}}
{{- end -}}

{{/* Merges every existing file of .paths, in order, into .dst. */}}
{{- define "layout.mergeFiles" -}}
{{- $ctx := . -}}
{{- range $path := .paths -}}
{{- $content := include "layout.parse" (dict "root" $ctx.root "catalog" $ctx.catalog "path" $path) | fromJson -}}
{{- include "layout.merge" (dict "dst" $ctx.dst "src" $content) -}}
{{- end -}}
{{- end -}}

{{/* Fails the render when .name is not an RFC 1123 label (SPEC §3.3). */}}
{{- define "layout.checkLabel" -}}
{{- if not (and (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" .name) (le (len .name) 63)) -}}
{{- fail (printf "%s: %s %q is not an RFC 1123 label (SPEC §3.3)" .context .what .name) -}}
{{- end -}}
{{- end -}}

{{/* Fails the render when property .name is undefined (SPEC §9.2.3). */}}
{{- define "layout.requireProperty" -}}
{{- if not (kindIs "string" .name) -}}
{{- fail (printf "%s: %v is not a property name; quote it, YAML reads it as a %s" .context .name (kindOf .name)) -}}
{{- end -}}
{{- if not (hasKey .props .name) -}}
{{- fail (printf "%s: undefined property %q" .context .name) -}}
{{- end -}}
{{- end -}}

{{/* The identity of resource .obj (SPEC §2). */}}
{{- define "layout.identity" -}}
{{- $metadata := .obj.metadata | default (dict) -}}
{{- if not (and .obj.apiVersion .obj.kind $metadata.name) -}}
{{- fail (printf "%s: apiVersion, kind and metadata.name are required" .context) -}}
{{- end -}}
{{- $apiVersion := toString .obj.apiVersion -}}
{{- $group := "core" -}}
{{- if contains "/" $apiVersion -}}
{{- $group = first (splitList "/" $apiVersion) -}}
{{- end -}}
{{- printf "%s/%s/%s" $group .obj.kind $metadata.name -}}
{{- with $metadata.namespace -}}
{{- printf "_%s" . -}}
{{- end -}}
{{- end -}}

{{/*
Checks the manifests/ directory of layer .layer against SPEC §8.1-§8.4, and
returns, as JSON, the identities it adds and the patches it applies, in order.
*/}}
{{- define "layout.manifests" -}}
{{- $io := dict "root" .root "catalog" .catalog -}}
{{- $dir := printf "%s/manifests" .layer -}}
{{- $kustomization := printf "%s/kustomization.yaml" $dir -}}
{{- $k := include "layout.parse" (merge (dict "path" $kustomization) $io) | fromJson -}}
{{- if or (ne (toString $k.kind) "Component") (ne (toString $k.apiVersion) "kustomize.config.k8s.io/v1alpha1") -}}
{{- fail (printf "%s: must be a Kustomize Component, apiVersion kustomize.config.k8s.io/v1alpha1 (SPEC §8.1)" $kustomization) -}}
{{- end -}}
{{- range $field, $_ := $k -}}
{{- if not (has $field (list "apiVersion" "kind" "resources" "patches")) -}}
{{- fail (printf "%s: field %q is not allowed (SPEC §8.2)" $kustomization $field) -}}
{{- end -}}
{{- end -}}
{{- $listed := list -}}
{{- range $resource := $k.resources | default (list) -}}
{{- if not (hasPrefix "resources/" (toString $resource)) -}}
{{- fail (printf "%s: resource %q is not under resources/ (SPEC §8.2)" $kustomization $resource) -}}
{{- end -}}
{{- $listed = append $listed (printf "%s/%s" $dir $resource) -}}
{{- end -}}
{{- range $patch := $k.patches | default (list) -}}
{{- if not (and (kindIs "map" $patch) (eq (len $patch) 1) (hasPrefix "patches/" (toString $patch.path))) -}}
{{- fail (printf "%s: a patch is only `path: patches/…` (SPEC §8.2)" $kustomization) -}}
{{- end -}}
{{- $listed = append $listed (printf "%s/%s" $dir $patch.path) -}}
{{- end -}}
{{- $files := include "layout.glob" (merge (dict "path" $dir) $io) | fromJsonArray -}}
{{- range $file := $files -}}
{{- if and (ne $file $kustomization) (not (has $file $listed)) -}}
{{- fail (printf "%s: not listed in %s (SPEC §8.2)" $file $kustomization) -}}
{{- end -}}
{{- end -}}
{{- $out := dict "resources" (list) "patches" (list) -}}
{{- range $file := $listed -}}
{{- if not (has $file $files) -}}
{{- fail (printf "%s: lists %s, which does not exist" $kustomization $file) -}}
{{- end -}}
{{- $documents := 0 -}}
{{- range $document := regexSplit "(?m)^---[ \t]*$" (include "layout.read" (merge (dict "path" $file) $io)) -1 -}}
{{- if regexMatch "(?m)^[^#\\s]" $document -}}
{{- $documents = add1 $documents -}}
{{- end -}}
{{- end -}}
{{- if ne $documents 1 -}}
{{- fail (printf "%s: holds %d resources instead of one (SPEC §8.3)" $file $documents) -}}
{{- end -}}
{{- $obj := include "layout.parse" (merge (dict "path" $file) $io) | fromJson -}}
{{- $identity := include "layout.identity" (dict "obj" $obj "context" $file) -}}
{{- if eq (toString ($obj.metadata | default (dict)).namespace) "default" -}}
{{- fail (printf "%s: sets namespace default, which Kustomize does not tell apart from none; leave it out (SPEC §8.3)" $file) -}}
{{- end -}}
{{- $kind := ternary "resources" "patches" (hasPrefix (printf "%s/resources/" $dir) $file) -}}
{{- if ne $file (printf "%s/%s/%s.yaml" $dir $kind $identity) -}}
{{- fail (printf "%s: must be named %s/%s.yaml after its content (SPEC §8.3)" $file $kind $identity) -}}
{{- end -}}
{{- if eq $kind "resources" -}}
{{- $_ := set $out "resources" (append $out.resources (dict "identity" $identity "apiVersion" (toString $obj.apiVersion) "file" $file)) -}}
{{- else -}}
{{- $_ := set $out "patches" (append $out.patches (dict "identity" $identity "apiVersion" (toString $obj.apiVersion) "delete" (eq (toString (index $obj "$patch")) "delete") "file" $file)) -}}
{{- end -}}
{{- end -}}
{{- toJson $out -}}
{{- end -}}

{{/*
The kinds Kustomize treats as cluster-scoped, measured on Kustomize 5.8 (the
one Argo CD 3.5 runs). A target naming `namespace: default` never matches
them, and the patch is silently dropped; any other kind, CRDs and recent
built-in kinds such as ValidatingAdmissionPolicy or ServiceCIDR included, is
namespaced to Kustomize.
*/}}
{{- define "layout.clusterScopedKinds" -}}
{{- list "APIService" "CertificateSigningRequest" "ClusterRole" "ClusterRoleBinding" "ComponentStatus" "CSIDriver" "CSINode" "CustomResourceDefinition" "IngressClass" "MutatingWebhookConfiguration" "Namespace" "Node" "PersistentVolume" "PriorityClass" "RuntimeClass" "StorageClass" "ValidatingWebhookConfiguration" "VolumeAttachment" | toJson -}}
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
{{- else if not (has (index $parts 1) (include "layout.clusterScopedKinds" . | fromJsonArray)) }}
{{- /* Kustomize matches an empty namespace against every namespace; "default"
   matches only the resources that set none. */}}
namespace: default
{{- end }}
{{- end -}}

{{/*
Kustomize patches setting mapped properties (SPEC §9.3): one JSON patch per
resource, one `replace` per pointer.
*/}}
{{- define "layout.patches" -}}
{{- $ctx := . -}}
{{- range $identity, $pointers := .mapping }}
{{- if not (kindIs "map" $pointers) }}
{{- fail (printf "%s: the mapping of %q must map JSON pointers to properties" $ctx.context $identity) }}
{{- end }}
- target:
    {{- include "layout.target" (dict "identity" $identity "context" $ctx.context) | trim | nindent 4 }}
  patch: |-
    {{- range $pointer, $property := $pointers }}
    - op: replace
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

{{/* The path of catalog file .path in the catalog's own repository. */}}
{{- define "layout.catalogPath" -}}
{{- $rel := trimPrefix "catalog/" .path -}}
{{- if .catalog.path -}}
{{- printf "%s/%s" .catalog.path $rel -}}
{{- else -}}
{{- $rel -}}
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

{{/*
Checks the files of app directory .layer: an app.yaml, values files and a
manifests directory, nothing else (SPEC §3.5, §8). Returns, as JSON, whether
it has manifests.
*/}}
{{- define "layout.checkAppDirectory" -}}
{{- $io := dict "root" .root "catalog" .catalog -}}
{{- $layer := .layer -}}
{{- $hasManifests := include "layout.read" (merge (dict "path" (printf "%s/manifests/kustomization.yaml" $layer)) $io) -}}
{{- range $file := include "layout.glob" (merge (dict "path" $layer) $io) | fromJsonArray -}}
{{- $rel := trimPrefix (printf "%s/" $layer) $file -}}
{{- if hasPrefix "manifests/" $rel -}}
{{- if not $hasManifests -}}
{{- fail (printf "%s: %s/manifests/ has no kustomization.yaml (SPEC §8.1)" $file $layer) -}}
{{- end -}}
{{- else if regexMatch "^values/[^/]+\\.yaml$" $rel -}}
{{- $source := trimSuffix ".yaml" (trimPrefix "values/" $rel) -}}
{{- if and (kindIs "slice" $.declared) (not (has $source $.declared)) -}}
{{- fail (printf "%s: no app.yaml of this app declares a source %q (SPEC §3.5)" $file $source) -}}
{{- end -}}
{{- else if ne $rel "app.yaml" -}}
{{- fail (printf "%s: matches nothing the layout defines (SPEC §3.5)" $file) -}}
{{- end -}}
{{- end -}}
{{- if $hasManifests -}}
{{- $_ := include "layout.manifests" (merge (dict "layer" $layer) $io) -}}
{{- end -}}
{{- end -}}

{{/* A scalar as a string, integers without the scientific notation of float64. */}}
{{- define "layout.scalar" -}}
{{- if and (kindIs "float64" .) (eq (floor .) .) -}}
{{- printf "%d" (int64 .) -}}
{{- else -}}
{{- toString . -}}
{{- end -}}
{{- end -}}
