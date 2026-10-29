/**
 * The lenses Time Drive's App Builder "Default Lens" property offers: All and
 * the lenses the org offers in the timeline's picker, named in the viewer's
 * language. Global because a managed package's dynamic picklist must be.
 */
global with sharing class TimeDriveLensPicklist extends VisualEditor.DynamicPickList {
  global override VisualEditor.DataRow getDefaultValue() {
    return new VisualEditor.DataRow(Label.Time_Drive_View_All, TimeDriveConfig.ALL_VIEW);
  }

  global override VisualEditor.DynamicPickListRows getValues() {
    VisualEditor.DynamicPickListRows rows = new VisualEditor.DynamicPickListRows();
    for (Time_Drive_View__mdt v : TimeDriveConfig.activeViews()) {
      rows.addRow(new VisualEditor.DataRow(TimeDriveConfig.viewLabel(v), v.DeveloperName));
    }
    return rows;
  }
}
