﻿using Common.SettingBackupAndRestore;
using Common.Types;
using System;
using System.Collections.Generic;
using VisualBlocks.Module.Base;


namespace VisualBlocks.Module.TypeString
{
    internal class StringContainerWriteDC : BlockItemDC, ICanBackupAndRestore
    {
        public BlockItemTriggerInputDC BlockItemTriggerInputDC { get; }
        public BlockItemTriggerOutputDC BlockItemTriggerOutputDC { get; }
        public BlockItemDataInputDC<Container<string>> BlockItemDataInputDC_Container { get; }
        public BlockItemDataInputDC<string> BlockItemDataInputDC_Data { get; }


        public StringContainerWriteDC(DependencyParams dependencyParams) : base(dependencyParams)
        {
            BlockItemDataInputDC_Container = new BlockItemDataInputDC<Container<string>>(dependencyParams);
            BlockItemDataInputDC_Data = new BlockItemDataInputDC<string>(dependencyParams);

            BlockItemTriggerInputDC = new BlockItemTriggerInputDC(dependencyParams);
            BlockItemTriggerInputDC.TriggerAction += BlockItemTriggerInputDC_TriggerAction;

            BlockItemTriggerOutputDC = new BlockItemTriggerOutputDC(dependencyParams);
        }

        private void BlockItemTriggerInputDC_TriggerAction(object sender, TriggerActionArgs e)
        {
            ExecuteOperation();
            BlockItemTriggerOutputDC.Trigger(e.Token);
        }

        private void BlockItemDataOutputDC_PullAction(object sender, EventArgs e)
        {
            // Húzásra csak akkor indítjuk a műveletet ha a trigger nincs csatlakoztatva
            if (!BlockItemTriggerInputDC.Connected)
                ExecuteOperation();
        }

        private void ExecuteOperation()
        {
            Container<string> container = BlockItemDataInputDC_Container.Value;

            if (container == null)
            {
                SetStatus(Status.Error, "A 'tároló' bemenetre nem érkezett kiértékelhető eredmény!");
                return;
            }

            string value = BlockItemDataInputDC_Data.Value;

            if (value == null)
            {
                SetStatus(Status.Error, "A bemenetre nem érkezett kiértékelhető eredmény!");
                return;
            }

            container.Value = value;
            SetStatus(Status.Ok);
        }

        public Dictionary<string, object> Backup()
        {
            BackupAndRestore bar = new BackupAndRestore();
            bar.SetData(nameof(Left), Left);
            bar.SetData(nameof(Top), Top);
            return bar.Container;
        }

        public void Restore(Dictionary<string, object> container)
        {
            BackupAndRestore bar = new BackupAndRestore(container);
            Left = bar.GetData<double>(nameof(Left));
            Top = bar.GetData<double>(nameof(Top));
        }
    }
}
