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
public class InlineMethodOptions extends RefactoringOptions {

  public static final List<InlineMethodOptions> EMPTY_LIST = List.of();

  /**
   * True if the method being inlined should be removed. It is an error if this field is true and
   * inlineAll is false.
   */
  private boolean deleteSource;

  /**
   * True if all invocations of the method should be inlined, or false if only the invocation site
   * used to create this refactoring should be inlined.
   */
  private boolean inlineAll;

  /**
   * Constructor for {@link InlineMethodOptions}.
   */
  public InlineMethodOptions(boolean deleteSource, boolean inlineAll) {
    this.deleteSource = deleteSource;
    this.inlineAll = inlineAll;
  }

  @Override
  public boolean equals(Object obj) {
    if (obj instanceof InlineMethodOptions other) {
      return
        other.deleteSource == deleteSource &&
        other.inlineAll == inlineAll;
    }
    return false;
  }

  public static InlineMethodOptions fromJson(JsonObject jsonObject) {
    boolean deleteSource = jsonObject.get("deleteSource").getAsBoolean();
    boolean inlineAll = jsonObject.get("inlineAll").getAsBoolean();
    return new InlineMethodOptions(deleteSource, inlineAll);
  }

  public static List<InlineMethodOptions> fromJsonArray(JsonArray jsonArray) {
    if (jsonArray == null) {
      return EMPTY_LIST;
    }
    List<InlineMethodOptions> list = new ArrayList<>(jsonArray.size());
    for (final JsonElement element : jsonArray) {
      list.add(fromJson(element.getAsJsonObject()));
    }
    return list;
  }

  /**
   * True if the method being inlined should be removed. It is an error if this field is true and
   * inlineAll is false.
   */
  public boolean deleteSource() {
    return deleteSource;
  }

  /**
   * True if all invocations of the method should be inlined, or false if only the invocation site
   * used to create this refactoring should be inlined.
   */
  public boolean inlineAll() {
    return inlineAll;
  }

  @Override
  public int hashCode() {
    return Objects.hash(
      deleteSource,
      inlineAll
    );
  }

  /**
   * True if the method being inlined should be removed. It is an error if this field is true and
   * inlineAll is false.
   */
  public void setDeleteSource(boolean deleteSource) {
    this.deleteSource = deleteSource;
  }

  /**
   * True if all invocations of the method should be inlined, or false if only the invocation site
   * used to create this refactoring should be inlined.
   */
  public void setInlineAll(boolean inlineAll) {
    this.inlineAll = inlineAll;
  }

  @Override
  public JsonObject toJson() {
    JsonObject jsonObject = new JsonObject();
    jsonObject.addProperty("deleteSource", deleteSource);
    jsonObject.addProperty("inlineAll", inlineAll);
    return jsonObject;
  }

  @Override
  public String toString() {
    StringBuilder builder = new StringBuilder();
    builder.append("[");
    builder.append("deleteSource=");
    builder.append(deleteSource);
    builder.append(", ");
    builder.append("inlineAll=");
    builder.append(inlineAll);
    builder.append("]");
    return builder.toString();
  }

}
