import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:personaltasklogger/db/repository/TemplateRepository.dart';
import 'package:personaltasklogger/model/TaskEvent.dart';
import 'package:personaltasklogger/model/TaskGroup.dart';
import 'package:personaltasklogger/model/TemplateId.dart';
import 'package:personaltasklogger/ui/utils.dart';
import 'package:personaltasklogger/util/dates.dart';
import 'package:fl_chart/fl_chart.dart';

import "package:collection/collection.dart";


class TaskEventStats extends StatefulWidget {

  List<TaskEvent> taskEvents;

  TaskEventStats(this.taskEvents);


  @override
  State<StatefulWidget> createState() {
    return _TaskEventStatsState();
  }
}

enum DataType {DURATION, COUNT}
enum SortBy {NAME, VALUE}
enum GroupBy {TASK_GROUP, TEMPLATE}

class _TaskEventStatsState extends State<TaskEventStats> {

  int _touchedIndex = -1;
  GroupBy _groupBy = GroupBy.TASK_GROUP;
  DataType _dataType = DataType.DURATION;

  late List<bool> _dataTypeSelection;
  int? _dataTypeIndex;

  @override
  void initState() {
    _dataTypeIndex = _dataType.index;
    _dataTypeSelection = List.generate(DataType.values.length, (index) => index == _dataTypeIndex);
    super.initState();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Journal Statistics"),
        actions: [
          IconButton(
              onPressed: () {
                setState(() {
                  _groupBy = _groupBy == GroupBy.TEMPLATE ? GroupBy.TASK_GROUP : GroupBy.TEMPLATE;
                });
              },
              icon: Icon(
                _groupBy == GroupBy.TEMPLATE ? Icons.task_alt : Icons.category_outlined,
              )),
        ],
      ),
      body: _createBody(),
    );
  }
  
  Widget _createBody() {

    Map<int?, List<TaskEvent>> groupedTaskEvents = groupBy(widget.taskEvents, (event) => event.taskGroupId);

    Map<int?, Map<TemplateId?, dynamic>> dataMap = groupedTaskEvents.map((taskGroupId, taskEvents) {
      if (_groupBy == GroupBy.TASK_GROUP) {
        return MapEntry(
            taskGroupId,
            Map.fromEntries([MapEntry(
              null,
              _aggregateValue(taskEvents))]));
      }
      else if (_groupBy == GroupBy.TEMPLATE) {
        Map<TemplateId?, List<TaskEvent>> groupedTemplates = groupBy(taskEvents, (event) => event.originTemplateId);

        Map<TemplateId?, dynamic> templateDataMap = groupedTemplates.map((templateId, subTaskEvents) {
          return MapEntry(
              templateId,
              _aggregateValue(subTaskEvents));
        });

        return MapEntry(taskGroupId, templateDataMap);
      }
      else {
        throw Exception("Programming error: unknown GroupBy: $_groupBy");
      }
    });

    final dataList = dataMap.entries
        .expand((e) => e.value.entries
            .map((templateMap) => SliceData(e.key, templateMap.key,  templateMap.value))
          )
        .sorted((a, b) {
          final c = _getDataValue(a.value).compareTo(_getDataValue(b.value));
          if (c == 0) {
            return a.taskGroupId??-1.compareTo(b.taskGroupId??-1);
          }
          return c;
    }).reversed;

    final totalValue = dataMap.entries
        .expand((e) => e.value.entries.map((e) => _getDataValue(e.value)))
        .fold(0.0, (double previous, current) => previous + current);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: _createDataButton(),
        ),
        AspectRatio(
          aspectRatio: MediaQuery.of(context).orientation == Orientation.portrait ? 1.2 : 2.7,
          child: PieChart(
            PieChartData(
                pieTouchData: PieTouchData(
                    touchCallback: (FlTouchEvent event, pieTouchResponse) {
                      setState(() {
                        if (!event.isInterestedForInteractions ||
                            pieTouchResponse == null ||
                            pieTouchResponse.touchedSection == null) {
                          _touchedIndex = -1;
                          return;
                        }
                        _touchedIndex =
                            pieTouchResponse.touchedSection!.touchedSectionIndex;
                      });
                    }),
                borderData: FlBorderData(
                  show: false,
                ),
                sectionsSpace: 0.9,
                centerSpaceRadius: _groupBy == GroupBy.TEMPLATE ? 30 : 0,
                sections: _showingSections(dataList, totalValue)),
          ),
        ),
        _buildLegend(dataList, totalValue),
      ],
    );
  }

  List<PieChartSectionData> _showingSections(Iterable<SliceData> dataList, num totalValue) {
    return dataList.mapIndexed((i, data) {
      final isTouched = i == _touchedIndex;
      final fontSize = isTouched ? 20.0 : 16.0;
      final r = _groupBy == GroupBy.TEMPLATE ? 70.0 : 100.0;
      final radius = isTouched ? r * 1.1 : r;

      final value = _getDataValue(data.value);

      int? taskGroupId = data.taskGroupId;
      final taskGroup = taskGroupId != null
          ? findPredefinedTaskGroupById(taskGroupId)
          : null;

      var percentValue = _valueToPercent(value, totalValue);
      return PieChartSectionData(
        color: data.templateId == null
            ? getSharpedColor(getTaskGroupColor(taskGroupId, false))
            : getTaskGroupColor(taskGroupId, data.templateId!.isVariant),
        value: value,
        title: _valueToPercentString(percentValue),
        radius: radius,
        titleStyle: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
        ),
        badgeWidget: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: (details) {
              setState(() {
                debugPrint("index=$i");
                _touchedIndex = i;
              });
            },
            onTapUp: (details) {
              setState(() {
                _touchedIndex = -1;
              });
            },
          child: _getTaskGroupIcon(taskGroup),
        ),
        titlePositionPercentageOffset: (percentValue <= 5) ? (i % 2 == 0 ? 0.9 : 0.8) : 0.6, // avoid overlapping titles
        badgePositionPercentageOffset: (percentValue <= 5 && i % 2 == 0) ? 1.45 : 1.2, // avoid overlapping icons
      );
    }).toList();
  }
  
  dynamic _aggregateValue(List<TaskEvent> taskEvents) {
      switch (_dataType) {
      case DataType.DURATION: {
        return _sumDuration(taskEvents);
      }
      case DataType.COUNT: {
        return taskEvents.length;
      }
    }
  }

  Duration _sumDuration(List<TaskEvent> taskEvents) {
    return taskEvents
        .map((event) => event.duration)
        .fold(Duration(), (previousDuration, duration) => previousDuration + duration);
  }

  double _getDataValue(dynamic value) {
    switch (_dataType) {
      case DataType.DURATION:
        {
          Duration duration = value;
          return duration.inMinutes.toDouble();
        }
      case DataType.COUNT:
        {
          int count = value;
          return count.toDouble();
        }
    }
  } 
  
  String _getDataValueAsString(dynamic value) {
    switch (_dataType) {
      case DataType.DURATION:
        {
          Duration duration = value;
          return formatDuration(duration);
        }
      case DataType.COUNT:
        {
          int count = value;
          return Items(count).toString();
        }
    }
  }

  Widget _buildLegend(Iterable<SliceData> dataList, double totalValue) {

    return Expanded(
      child: FutureBuilder(
        future: _createLegendElements(dataList, totalValue),
        builder: (context, AsyncSnapshot<List<Container>> snapshot) {
          if (snapshot.hasData) {
            return ListView.builder(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: snapshot.data!.length,
              itemBuilder: (context, index) {
                return snapshot.data![index];
              },
            );
          }
          else {
            return Text("loading");
          }
        },
      ),
    );

  }

  Future<List<Container>> _createLegendElements(Iterable<SliceData> dataList, double totalValue) async {
    final legendElementFutures = dataList.mapIndexed((i, data) async {
      final isTouched = i == _touchedIndex;
      final fontSize = isTouched ? 16.1 : 16.0;
      final fontWeight = isTouched ? FontWeight.bold : null;
    
      int? taskGroupId = data.taskGroupId;
      final taskGroup = taskGroupId != null
          ? findPredefinedTaskGroupById(taskGroupId)
          : null;
    
      final template = data.templateId != null ? await TemplateRepository.getById(data.templateId!) : null;

      final groupedByPresentation = Row(
          children: [
            taskGroup?.getIcon(true) ?? Text(""),
            Text(template?.title ?? taskGroup?.name ?? "",
              style: TextStyle(
              fontSize: isTouched ? 14.1 : 14.0,
              fontWeight: fontWeight)),
          ]);
    
      return Container(
        height: 30,
       // color: taskGroup != null ? taskGroup.backgroundColor : null,
        color: data.templateId == null
            ? (taskGroup != null ? taskGroup.backgroundColor : null)
            : getTaskGroupColor(taskGroupId, data.templateId!.isVariant),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: (details) {
            setState(() {
              _touchedIndex = i;
            });
          },
          onTapUp: (details) {
            setState(() {
              _touchedIndex = -1;
            });
          },
          child: Row(
            children: [
              groupedByPresentation,
              Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 4, 0),
                child: Text(_getDataValueAsString(data.value),
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: fontWeight)
                ),
              )
            ],
          ),
        ),
      );
    }).toList();
    
    final totalValueAsString = _dataType == DataType.DURATION
      ? formatDuration(Duration(minutes: totalValue.toInt()))
      : Items(totalValue.toInt());
    
    legendElementFutures.insert(0, Future.value(Container(
      height: 30, child: Text("Total $totalValueAsString",
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: FontWeight.bold)))
    ));
    return Future.wait(legendElementFutures);
  }

  Icon _getTaskGroupIcon(TaskGroup? taskGroup) {
    return taskGroup != null
        ? taskGroup.getIcon(true)
        : Icon(Icons.question_mark_outlined,
          color: Colors.grey,);
  }

  _valueToPercentString(int percentValue) {
    return "${percentValue}%";
  }

  int _valueToPercent(double value, num total) => (value * 100 / total).round();

  Widget _createDataButton() {
    return ToggleButtons(
      borderRadius: BorderRadius.all(Radius.circular(5.0)),
      renderBorder: true,
      borderWidth: 1.5,
      borderColor: Colors.grey,
      color: Colors.grey.shade600,
      selectedBorderColor: Colors.blue,
      children: [
        SizedBox(
          width: 75,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.timer_outlined),
              const Text("Duration", textAlign: TextAlign.center),
            ],
          )
        ),
        SizedBox(
          width: 75,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.numbers_outlined),
              const Text("Total count", textAlign: TextAlign.center),
            ],
          )
        ),
      ],
      isSelected: _dataTypeSelection,
      onPressed: (int index) {
        setState(() {
          if (_dataTypeIndex != null) {
            _dataTypeSelection[_dataTypeIndex!] = false;
          }
          _dataTypeSelection[index] = true;
          _dataType = DataType.values.elementAt(index);
          _dataTypeIndex = index;
        });
      },
    );
  }
}

class SliceData {
  int? taskGroupId;
  TemplateId? templateId;
  dynamic value;

  SliceData(this.taskGroupId, this.templateId, this.value);
}
