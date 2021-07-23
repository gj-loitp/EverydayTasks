import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:personaltasklogger/model/Severity.dart';
import 'package:personaltasklogger/model/TaskGroup.dart';

Widget severityToIcon(Severity severity) {
  List<Icon> icons = List.generate(
      severity.index + 1, (index) => Icon(Icons.fitness_center_rounded));

  return Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: icons,
  );
}

Color getTaskGroupColor(int? taskGroupId, bool lessShaded) {
  final taskGroupColor = taskGroupId != null ? findTaskGroupById(taskGroupId).colorRGB : null;
  return getShadedColor(taskGroupColor, lessShaded);
}

Color getShadedColor(Color? colorRGB, bool lessShaded) {
  var color = colorRGB ?? Colors.lime.shade100;
  return shadeColor(lessShaded, color);
}

Color shadeColor(bool lessShaded, Color color) {
  if (lessShaded) {
    return color.withAlpha(50);
  }
  else {
    return color;
  }
}