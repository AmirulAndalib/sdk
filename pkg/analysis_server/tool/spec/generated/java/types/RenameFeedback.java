/*
 * Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
 * for details. All rights reserved. Use of this source code is governed by a
 * BSD-style license that can be found in the LICENSE file.
 *
 * This file has been automatically generated. Please do not edit it manually.
 * To regenerate the file, use the script "pkg/analysis_server/tool/spec/generate_files".
 */
package org.dartlang.analysis.server.protocol;

import java.util.Arrays;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.stream.Collectors;
import com.google.dart.server.utilities.general.JsonUtilities;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonPrimitive;

/**
 * @coverage dart.server.generated.types
 */
@SuppressWarnings("unused")
public class RenameFeedback extends RefactoringFeedback {

  public static final List<RenameFeedback> EMPTY_LIST = List.of();

  /**
   * The offset to the beginning of the name selected to be renamed, or -1 if the name does not exist
   * yet.
   */
  private final int offset;

  /**
   * The length of the name selected to be renamed.
   */
  private final int length;

  /**
   * The human-readable description of the kind of element being renamed (such as "class" or
   * "function type alias").
   */
  private final String elementKindName;

  /**
   * The old name of the element before the refactoring.
   */
  private final String oldName;

  /**
   * Constructor for {@link RenameFeedback}.
   */
  public RenameFeedback(int offset, int length, String elementKindName, String oldName) {
    this.offset = offset;
    this.length = length;
    this.elementKindName = elementKindName;
    this.oldName = oldName;
  }

  @Override
  public boolean equals(Object obj) {
    if (obj instanceof RenameFeedback other) {
      return
        other.offset == offset &&
        other.length == length &&
        Objects.equals(other.elementKindName, elementKindName) &&
        Objects.equals(other.oldName, oldName);
    }
    return false;
  }

  public static RenameFeedback fromJson(JsonObject jsonObject) {
    int offset = jsonObject.get("offset").getAsInt();
    int length = jsonObject.get("length").getAsInt();
    String elementKindName = jsonObject.get("elementKindName").getAsString();
    String oldName = jsonObject.get("oldName").getAsString();
    return new RenameFeedback(offset, length, elementKindName, oldName);
  }

  public static List<RenameFeedback> fromJsonArray(JsonArray jsonArray) {
    if (jsonArray == null) {
      return EMPTY_LIST;
    }
    List<RenameFeedback> list = new ArrayList<>(jsonArray.size());
    for (final JsonElement element : jsonArray) {
      list.add(fromJson(element.getAsJsonObject()));
    }
    return list;
  }

  /**
   * The human-readable description of the kind of element being renamed (such as "class" or
   * "function type alias").
   */
  public String getElementKindName() {
    return elementKindName;
  }

  /**
   * The length of the name selected to be renamed.
   */
  public int getLength() {
    return length;
  }

  /**
   * The offset to the beginning of the name selected to be renamed, or -1 if the name does not exist
   * yet.
   */
  public int getOffset() {
    return offset;
  }

  /**
   * The old name of the element before the refactoring.
   */
  public String getOldName() {
    return oldName;
  }

  @Override
  public int hashCode() {
    return Objects.hash(
      offset,
      length,
      elementKindName,
      oldName
    );
  }

  @Override
  public JsonObject toJson() {
    JsonObject jsonObject = new JsonObject();
    jsonObject.addProperty("offset", offset);
    jsonObject.addProperty("length", length);
    jsonObject.addProperty("elementKindName", elementKindName);
    jsonObject.addProperty("oldName", oldName);
    return jsonObject;
  }

  @Override
  public String toString() {
    StringBuilder builder = new StringBuilder();
    builder.append("[");
    builder.append("offset=");
    builder.append(offset);
    builder.append(", ");
    builder.append("length=");
    builder.append(length);
    builder.append(", ");
    builder.append("elementKindName=");
    builder.append(elementKindName);
    builder.append(", ");
    builder.append("oldName=");
    builder.append(oldName);
    builder.append("]");
    return builder.toString();
  }

}
